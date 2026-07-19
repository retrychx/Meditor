#!/usr/bin/env bash
# 部署官网到 Cloudflare Worker：
#   docs/index.html + docs/images/ → .site-dist（暂存）→ wrangler deploy
# 用法：
#   bash scripts/deploy-docs.sh            # 部署
# 需要：已 npx wrangler login，或 CLOUDFLARE_API_TOKEN 环境变量。
set -euo pipefail
cd "$(dirname "$0")/.."

DIST=.site-dist
rm -rf "$DIST"
mkdir -p "$DIST"
cp docs/index.html "$DIST/"
cp -R docs/images "$DIST/images"

npx --yes wrangler deploy
rm -rf "$DIST"
