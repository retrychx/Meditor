#!/usr/bin/env bash
# 部署官网到 Cloudflare Worker（website/ 目录 → wrangler deploy）
# 需要：已 npx wrangler login，或 CLOUDFLARE_API_TOKEN 环境变量。
set -euo pipefail
cd "$(dirname "$0")/.."

npx --yes wrangler deploy
