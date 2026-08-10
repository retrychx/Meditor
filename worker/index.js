// MEditor 分享服务：文档发布 + 应用更新分发 + 官网静态站
//   POST /api/share           发布渲染后的 HTML（需 Bearer $SHARE_TOKEN）→ 返回 {url}
//   GET  /d/:id               读取已发布文档（KV）
//   GET  /update/appcast.xml  Sparkle 更新 feed（KV）
//   GET  /update/pkg          最新安装包 zip（KV）
//   POST /api/update/*        发布更新（需 Bearer $UPDATE_TOKEN，CI 打 tag 时调用）
//   其余路径                  → 官网静态资源（[assets] = ./website）

const MAX_HTML_BYTES = 4 * 1024 * 1024; // 4MB
const ID_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
const ID_LENGTH = 10;

function makeID() {
  const bytes = new Uint8Array(ID_LENGTH);
  crypto.getRandomValues(bytes);
  let id = "";
  for (const b of bytes) id += ID_ALPHABET[b % ID_ALPHABET.length];
  return id;
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8" },
  });
}

function notFound() {
  const page = `<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>404 · MEditor</title>
<style>body{font-family:-apple-system,system-ui,sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0;background:#F4F5F2;color:#1B2434}
a{color:#C0392B;text-decoration:none}</style></head>
<body><div><h1>链接不存在或已删除</h1><p><a href="/">返回 MEditor 首页</a></p></div></body></html>`;
  return new Response(page, {
    status: 404,
    headers: { "Content-Type": "text/html; charset=utf-8" },
  });
}

async function handleShare(request, env) {
  // 未配置 SHARE_TOKEN 时一律拒绝（宁可全关，不留裸奔接口）
  const expected = env.SHARE_TOKEN;
  if (!expected) return json({ error: "share not enabled" }, 503);
  const auth = request.headers.get("Authorization") || "";
  if (auth !== `Bearer ${expected}`) return json({ error: "unauthorized" }, 401);

  const length = Number(request.headers.get("Content-Length") || 0);
  if (length > MAX_HTML_BYTES * 2) return json({ error: "too large" }, 413);

  let payload;
  try {
    payload = await request.json();
  } catch {
    return json({ error: "invalid json" }, 400);
  }
  const title = String(payload?.title || "未命名").slice(0, 200);
  const html = String(payload?.html || "");
  if (!html) return json({ error: "empty html" }, 400);
  if (new TextEncoder().encode(html).length > MAX_HTML_BYTES) {
    return json({ error: "too large" }, 413);
  }

  const id = makeID();
  await env.SHARES.put(id, html, {
    metadata: { title, createdAt: new Date().toISOString() },
  });
  const origin = new URL(request.url).origin;
  return json({ id, url: `${origin}/d/${id}` });
}

async function handleDoc(env, id) {
  if (!/^[A-Za-z0-9]{10}$/.test(id)) return notFound();
  const html = await env.SHARES.get(id);
  if (html === null) return notFound();
  return new Response(html, {
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "public, max-age=300",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

// ── 应用更新（Sparkle appcast + 安装包，KV 存储，单槽只留最新版） ──
//   GET  /update/appcast.xml   Sparkle feed（CI 发版时覆写）
//   GET  /update/pkg           最新安装包 zip（appcast 里的 enclosure 指向这里）
//   POST /api/update/appcast   发布 appcast（Bearer UPDATE_TOKEN，body=XML 文本）
//   POST /api/update/pkg       发布安装包（Bearer UPDATE_TOKEN，body=zip 二进制）
// KV 单值上限 25MiB——当前 zip ~9MB，超了要换 R2。

const MAX_PKG_BYTES = 24 * 1024 * 1024;

function checkUpdateAuth(request, env) {
  const expected = env.UPDATE_TOKEN;
  if (!expected) return json({ error: "update not enabled" }, 503);
  const auth = request.headers.get("Authorization") || "";
  if (auth !== `Bearer ${expected}`) return json({ error: "unauthorized" }, 401);
  return null;
}

async function handleUpdatePublish(request, env, kind) {
  const denied = checkUpdateAuth(request, env);
  if (denied) return denied;

  const length = Number(request.headers.get("Content-Length") || 0);
  if (length > MAX_PKG_BYTES) return json({ error: "too large" }, 413);

  if (kind === "appcast") {
    const xml = await request.text();
    if (!xml.includes("<rss") || !xml.includes("sparkle:version")) {
      return json({ error: "invalid appcast" }, 400);
    }
    await env.UPDATES.put("appcast.xml", xml);
    return json({ ok: true, bytes: new TextEncoder().encode(xml).length });
  }

  // pkg：直接透传请求流到 KV，避免整包进内存
  if (!request.body) return json({ error: "empty body" }, 400);
  await env.UPDATES.put("pkg/latest.zip", request.body, {
    metadata: { publishedAt: new Date().toISOString() },
  });
  return json({ ok: true, bytes: length });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === "/api/share") {
      if (request.method !== "POST") return json({ error: "method not allowed" }, 405);
      return handleShare(request, env);
    }

    if (url.pathname === "/api/update/appcast" || url.pathname === "/api/update/pkg") {
      if (request.method !== "POST") return json({ error: "method not allowed" }, 405);
      return handleUpdatePublish(request, env, url.pathname.endsWith("appcast") ? "appcast" : "pkg");
    }

    if (url.pathname === "/update/appcast.xml") {
      if (request.method !== "GET") return json({ error: "method not allowed" }, 405);
      const xml = await env.UPDATES.get("appcast.xml");
      if (xml === null) return notFound();
      return new Response(xml, {
        headers: {
          "Content-Type": "application/xml; charset=utf-8",
          // Sparkle 每次检查都拉这个文件——别缓存，否则发版后客户端要延迟才能看到
          "Cache-Control": "no-cache",
        },
      });
    }

    if (url.pathname === "/update/pkg") {
      if (request.method !== "GET") return json({ error: "method not allowed" }, 405);
      const pkg = await env.UPDATES.get("pkg/latest.zip", "stream");
      if (pkg === null) return notFound();
      return new Response(pkg, {
        headers: {
          "Content-Type": "application/zip",
          "Cache-Control": "public, max-age=300",
        },
      });
    }

    if (url.pathname.startsWith("/d/")) {
      if (request.method !== "GET") return json({ error: "method not allowed" }, 405);
      const id = url.pathname.slice(3);
      return handleDoc(env, id);
    }

    // 官网静态资源
    return env.ASSETS.fetch(request);
  },
};
