// MEditor 分享服务：文档发布 + 应用更新分发 + 官网静态站
//   POST /api/share           发布渲染后的 HTML（Bearer $SHARE_TOKEN=免费档 / $PRO_TOKENS 之一=Pro）→ 返回 {url}
//   GET  /d/:id               读取已发布文档（KV；免费档 30 天过期 → 410 友好页）
//   GET  /update/appcast.xml  Sparkle 更新 feed（KV）
//   GET  /update/pkg          最新安装包 zip（KV）
//   POST /api/update/*        发布更新（需 Bearer $UPDATE_TOKEN，CI 打 tag 时调用）
//   其余路径                  → 官网静态资源（[assets] = ./website）
//
// 免费档规则（商业化验证，未接支付）：
//   - 每个发布 token 每月最多 FREE_MONTHLY_QUOTA 篇（KV 计数，key=quota:<token哈希>:<YYYY-MM>，次月 1 日 UTC 重置）
//   - 免费文档 30 天过期；超限返回 429 {error, limit, resetsAt}
//   - 免费档阅读页底部注入 "Published with MEditor" 品牌页脚
// Pro token（env.PRO_TOKENS，逗号分隔的 wrangler secret）：不限量、不过期、无页脚

const MAX_HTML_BYTES = 4 * 1024 * 1024; // 4MB
const ID_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
const ID_LENGTH = 10;

export const FREE_MONTHLY_QUOTA = 20;
export const FREE_DOC_TTL_DAYS = 30;

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

// ── 免费档 / Pro 判定（纯函数，node --test 直接覆盖） ──

// token 是否在 PRO_TOKENS（逗号分隔）里。只比对、不回显，不泄漏有效 token 列表。
export function isProToken(token, proTokensEnv) {
  if (!token || !proTokensEnv) return false;
  return proTokensEnv.split(",").some((t) => t.trim() !== "" && t.trim() === token);
}

// 当月 key（UTC），如 "2026-08"。
export function monthKey(now) {
  return `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, "0")}`;
}

// 次月 1 日 00:00 UTC 的 ISO 串——免费档额度的重置时间点。
export function nextMonthStartISO(now) {
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 1)).toISOString();
}

// 免费档文档是否已过 30 天保留期（Pro 文档 metadata.tier === "pro"，永不过期）。
// 上线前发布的存量文档没有 tier 字段，视为 Pro——避免部署后旧链接立即 410。
export function isDocExpired(metadata, now) {
  if (!metadata || metadata.tier !== "free" || !metadata.createdAt) return false;
  const created = Date.parse(metadata.createdAt);
  if (Number.isNaN(created)) return false;
  return now.getTime() - created > FREE_DOC_TTL_DAYS * 24 * 60 * 60 * 1000;
}

// 免费档阅读页底部注入一行小字品牌页脚（幂等：已注入过就不再重复加）。
export function injectFooter(html, origin) {
  if (html.includes("meditor-brand-footer")) return html;
  const footer = `<div class="meditor-brand-footer" style="margin-top:48px;padding-top:16px;border-top:1px solid rgba(128,128,128,.25);font:12px -apple-system,system-ui,sans-serif;text-align:center;opacity:.55">Published with <a href="${origin}" style="color:inherit">MEditor</a> · Free plan</div>`;
  const i = html.toLowerCase().lastIndexOf("</body>");
  return i === -1 ? html + footer : html.slice(0, i) + footer + html.slice(i);
}

// 计量 KV key——token 只存哈希，不落在明文的 KV key 里。
async function quotaKey(token, now) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token));
  const hex = [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
  return `quota:${hex.slice(0, 24)}:${monthKey(now)}`;
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

// 免费档文档过期的友好落地页（410 Gone——语义上比 404 准确，也便于客户端区分）
function expired() {
  const page = `<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>410 · MEditor</title>
<style>body{font-family:-apple-system,system-ui,sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0;background:#F4F5F2;color:#1B2434}
a{color:#C0392B;text-decoration:none}.muted{color:#5D6673}</style></head>
<body><div><h1>链接已过期</h1><p class="muted">免费档发布的文档保留 ${FREE_DOC_TTL_DAYS} 天。<br>This link has expired — free-plan documents are kept for ${FREE_DOC_TTL_DAYS} days.</p>
<p><a href="/">返回 MEditor 首页</a></p></div></body></html>`;
  return new Response(page, {
    status: 410,
    headers: { "Content-Type": "text/html; charset=utf-8" },
  });
}

async function handleShare(request, env) {
  // 未配置 SHARE_TOKEN 时一律拒绝（宁可全关，不留裸奔接口）
  const expected = env.SHARE_TOKEN;
  if (!expected) return json({ error: "share not enabled" }, 503);
  const auth = request.headers.get("Authorization") || "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7).trim() : "";
  const pro = isProToken(token, env.PRO_TOKENS);
  if (!pro && token !== expected) return json({ error: "unauthorized" }, 401);

  const length = Number(request.headers.get("Content-Length") || 0);
  if (length > MAX_HTML_BYTES * 2) return json({ error: "too large" }, 413);

  let payload;
  try {
    payload = await request.json();
  } catch {
    return json({ error: "invalid json" }, 400);
  }
  const title = String(payload?.title || "未命名").slice(0, 200);
  let html = String(payload?.html || "");
  if (!html) return json({ error: "empty html" }, 400);
  if (new TextEncoder().encode(html).length > MAX_HTML_BYTES) {
    return json({ error: "too large" }, 413);
  }

  const origin = new URL(request.url).origin;
  const now = new Date();

  // 免费档：按月配额（读-改-写，非原子；商业化验证阶段可接受的轻微超发）
  if (!pro) {
    const key = await quotaKey(token, now);
    const used = Number((await env.SHARES.get(key)) || 0);
    if (used >= FREE_MONTHLY_QUOTA) {
      return json(
        { error: "monthly quota exceeded", limit: FREE_MONTHLY_QUOTA, resetsAt: nextMonthStartISO(now) },
        429
      );
    }
    await env.SHARES.put(key, String(used + 1));
    html = injectFooter(html, origin);
  }

  const id = makeID();
  await env.SHARES.put(id, html, {
    metadata: { title, createdAt: now.toISOString(), tier: pro ? "pro" : "free" },
  });
  return json({ id, url: `${origin}/d/${id}` });
}

async function handleDoc(env, id) {
  if (!/^[A-Za-z0-9]{10}$/.test(id)) return notFound();
  const { value: html, metadata } = await env.SHARES.getWithMetadata(id);
  if (html === null) return notFound();
  if (isDocExpired(metadata, new Date())) return expired();
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
          // 官网下载按钮也指向这里——给个像样的文件名（Sparkle 会忽略这个头）
          "Content-Disposition": 'attachment; filename="MEditor.zip"',
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
