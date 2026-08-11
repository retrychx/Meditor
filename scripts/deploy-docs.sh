#!/usr/bin/env bash
# 部署官网 + 后端到 Cloudflare，两个入口同一份代码、同一对 KV：
#   1) Workers  https://meditor-app.863129776.workers.dev（App 更新检查/分享写死这个，不动）
#   2) Pages    https://meditorapp.pages.dev（对外官网域名，配置见 wrangler.pages.toml）
# 需要：已 npx wrangler login，或 CLOUDFLARE_API_TOKEN 环境变量。
set -euo pipefail
cd "$(dirname "$0")/.."

npx --yes wrangler deploy

# Pages 高级模式只认输出目录根部的 _worker.js——部署时从 worker/index.js
# 临时拷贝，结束后删掉（留在 website/ 里会被 Workers 版当静态资源传上去）。
# Pages 不认 --config 指定的配置文件，配置放在 pages/wrangler.toml，cd 进去跑。
cp worker/index.js website/_worker.js
trap 'rm -f website/_worker.js' EXIT
(cd pages && npx --yes wrangler pages deploy)
