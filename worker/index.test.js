// worker/index.js 的单测：node --test（Node ≥ 20，全局 Request/Response/crypto 可用）。
// env 用内存版 KV mock，覆盖：免费档配额、30 天过期、品牌页脚、Pro 豁免、鉴权。

import test from "node:test";
import assert from "node:assert/strict";
import worker, {
  FREE_MONTHLY_QUOTA,
  isProToken,
  isDocExpired,
  injectFooter,
  monthKey,
  nextMonthStartISO,
} from "./index.js";

const SHARE_TOKEN = "free-token";
const PRO_TOKENS = "pro-alpha, pro-beta";

// ── 内存 KV mock（只实现 worker 用到的 get/put/getWithMetadata） ──
class MockKV {
  constructor() {
    this.map = new Map(); // key -> {value, metadata}
  }
  async get(key) {
    return this.map.get(key)?.value ?? null;
  }
  async put(key, value, opts = {}) {
    this.map.set(key, { value, metadata: opts.metadata ?? null });
  }
  async getWithMetadata(key) {
    const entry = this.map.get(key);
    return entry
      ? { value: entry.value, metadata: entry.metadata }
      : { value: null, metadata: null };
  }
}

function makeEnv() {
  return {
    SHARES: new MockKV(),
    UPDATES: new MockKV(),
    ASSETS: { fetch: async () => new Response("site") },
    SHARE_TOKEN,
    PRO_TOKENS,
  };
}

function publishRequest(token, html = "<!DOCTYPE html><html><body><h1>hi</h1></body></html>") {
  return new Request("https://share.example.com/api/share", {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({ title: "t", html }),
  });
}

// ── 纯函数 ──

test("isProToken: 命中/未命中/空值", () => {
  assert.equal(isProToken("pro-alpha", PRO_TOKENS), true);
  assert.equal(isProToken("pro-beta", PRO_TOKENS), true); // 逗号后空格 trim
  assert.equal(isProToken("free-token", PRO_TOKENS), false);
  assert.equal(isProToken("", PRO_TOKENS), false);
  assert.equal(isProToken("pro-alpha", undefined), false);
  assert.equal(isProToken("pro-alpha", ""), false);
  assert.equal(isProToken("pro-alpha", ",,,"), false); // 空条目不算命中
});

test("monthKey / nextMonthStartISO: 月份格式与跨年重置", () => {
  assert.equal(monthKey(new Date("2026-08-15T10:00:00Z")), "2026-08");
  assert.equal(nextMonthStartISO(new Date("2026-08-15T10:00:00Z")), "2026-09-01T00:00:00.000Z");
  assert.equal(nextMonthStartISO(new Date("2026-12-31T23:00:00Z")), "2027-01-01T00:00:00.000Z");
});

test("isDocExpired: 免费 30 天过期，Pro/存量无 tier/坏数据不过期", () => {
  const now = new Date("2026-08-24T00:00:00Z");
  const old = { createdAt: "2026-07-20T00:00:00Z", tier: "free" }; // 35 天前
  const fresh = { createdAt: "2026-08-20T00:00:00Z", tier: "free" };
  assert.equal(isDocExpired(old, now), true);
  assert.equal(isDocExpired(fresh, now), false);
  assert.equal(isDocExpired({ ...old, tier: "pro" }, now), false);
  // 上线前的存量文档没有 tier 字段，视为 Pro——部署后旧链接不应立即 410
  assert.equal(isDocExpired({ createdAt: "2026-01-01T00:00:00Z" }, now), false);
  assert.equal(isDocExpired(null, now), false);
  assert.equal(isDocExpired({}, now), false);
  assert.equal(isDocExpired({ createdAt: "not-a-date" }, now), false);
});

test("injectFooter: 插入 </body> 前、幂等、无 body 时追加", () => {
  const html = "<html><body><p>x</p></body></html>";
  const out = injectFooter(html, "https://share.example.com");
  assert.ok(out.includes("meditor-brand-footer"));
  assert.ok(out.indexOf("meditor-brand-footer") < out.indexOf("</body>"));
  assert.equal(injectFooter(out, "https://share.example.com"), out); // 幂等
  assert.ok(injectFooter("<p>no body</p>", "o").endsWith("</div>"));
});

// ── 发布流程 ──

test("免费档发布成功：返回 url、注入品牌页脚、metadata 标记 free", async () => {
  const env = makeEnv();
  const res = await worker.fetch(publishRequest(SHARE_TOKEN), env);
  assert.equal(res.status, 200);
  const { id, url } = await res.json();
  assert.equal(url, `https://share.example.com/d/${id}`);
  const { value, metadata } = await env.SHARES.getWithMetadata(id);
  assert.ok(value.includes("meditor-brand-footer"));
  assert.equal(metadata.tier, "free");
});

test("Pro token 发布：不计量、无页脚、metadata 标记 pro", async () => {
  const env = makeEnv();
  const res = await worker.fetch(publishRequest("pro-alpha"), env);
  assert.equal(res.status, 200);
  const { id } = await res.json();
  const { value, metadata } = await env.SHARES.getWithMetadata(id);
  assert.ok(!value.includes("meditor-brand-footer"));
  assert.equal(metadata.tier, "pro");
});

test("免费档配额：前 20 篇成功，第 21 篇 429 + {error, limit, resetsAt}", async () => {
  const env = makeEnv();
  for (let i = 0; i < FREE_MONTHLY_QUOTA; i++) {
    const res = await worker.fetch(publishRequest(SHARE_TOKEN), env);
    assert.equal(res.status, 200, `第 ${i + 1} 篇应成功`);
  }
  const res = await worker.fetch(publishRequest(SHARE_TOKEN), env);
  assert.equal(res.status, 429);
  const body = await res.json();
  assert.equal(body.limit, FREE_MONTHLY_QUOTA);
  assert.ok(body.error);
  assert.ok(/^\d{4}-\d{2}-01T00:00:00\.000Z$/.test(body.resetsAt));
});

test("Pro token 不受配额限制", async () => {
  const env = makeEnv();
  for (let i = 0; i < FREE_MONTHLY_QUOTA + 5; i++) {
    const res = await worker.fetch(publishRequest("pro-beta"), env);
    assert.equal(res.status, 200, `Pro 第 ${i + 1} 篇应成功`);
  }
});

test("计量不泄漏 token：quota key 是哈希，不含明文 token", async () => {
  const env = makeEnv();
  await worker.fetch(publishRequest(SHARE_TOKEN), env);
  const keys = [...env.SHARES.map.keys()];
  const quotaKeys = keys.filter((k) => k.startsWith("quota:"));
  assert.equal(quotaKeys.length, 1);
  assert.ok(!quotaKeys[0].includes(SHARE_TOKEN));
});

test("鉴权：错误 token 401；未配置 SHARE_TOKEN 时 503", async () => {
  const env = makeEnv();
  assert.equal((await worker.fetch(publishRequest("wrong"), env)).status, 401);
  const env2 = makeEnv();
  delete env2.SHARE_TOKEN;
  assert.equal((await worker.fetch(publishRequest("pro-alpha"), env2)).status, 503);
});

// ── 阅读页 ──

test("免费文档 30 天后访问 → 410 友好页；未过期正常返回", async () => {
  const env = makeEnv();
  const res = await worker.fetch(publishRequest(SHARE_TOKEN), env);
  const { id } = await res.json();

  const okRes = await worker.fetch(new Request(`https://share.example.com/d/${id}`), env);
  assert.equal(okRes.status, 200);

  // 把 createdAt 改成 31 天前，模拟过期
  const entry = env.SHARES.map.get(id);
  entry.metadata = {
    ...entry.metadata,
    createdAt: new Date(Date.now() - 31 * 24 * 3600 * 1000).toISOString(),
  };
  const goneRes = await worker.fetch(new Request(`https://share.example.com/d/${id}`), env);
  assert.equal(goneRes.status, 410);
  assert.ok((await goneRes.text()).includes("链接已过期"));
});

test("Pro 文档 31 天后仍可访问（不过期）", async () => {
  const env = makeEnv();
  const res = await worker.fetch(publishRequest("pro-alpha"), env);
  const { id } = await res.json();
  const entry = env.SHARES.map.get(id);
  entry.metadata = {
    ...entry.metadata,
    createdAt: new Date(Date.now() - 31 * 24 * 3600 * 1000).toISOString(),
  };
  const docRes = await worker.fetch(new Request(`https://share.example.com/d/${id}`), env);
  assert.equal(docRes.status, 200);
});
