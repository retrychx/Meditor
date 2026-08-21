#!/usr/bin/env bash
# AI 自审脚本——单作者项目的"第二双眼睛"。
#
# 用法：
#   bash scripts/ai_review.sh            # 审查工作区未提交改动
#   bash scripts/ai_review.sh <base>     # 审查 base..HEAD 的改动（如 origin/main）
#   bash scripts/ai_review.sh --no-pipe  # 只生成 review 提示词，不调用 Claude CLI
#
# 流程：1) 快速质量自检（lint） 2) 生成带项目上下文的 diff 审查提示词
#       3) 有 claude CLI 时直接交给它审查，否则打印提示词供手动使用。
set -euo pipefail
cd "$(dirname "$0")/.."

BASE="${1:-}"
PIPE_CLAUDE=1
if [[ "$BASE" == "--no-pipe" ]]; then BASE=""; PIPE_CLAUDE=0; fi

echo "==> 1/3 快速质量自检"
if command -v swiftlint &>/dev/null; then
  swiftlint lint --config .swiftlint.yml Sources || true
else
  echo "    (swiftlint 未安装，跳过 lint)"
fi

echo "==> 2/3 收集 diff"
if [[ -n "$BASE" ]]; then
  DIFF="$(git diff "$BASE"...HEAD 2>/dev/null || git diff "$BASE" HEAD)"
else
  DIFF="$(git diff)"
fi
if [[ -z "$DIFF" ]]; then
  echo "    没有待审查的改动（工作区干净且未指定 base）。"
  exit 0
fi

echo "==> 3/3 生成审查提示词"
PROMPT_FILE="$(mktemp)"
cat > "$PROMPT_FILE" <<'EOF'
你是 Meditor（macOS/iOS 的 SwiftUI Markdown 文档工作台）的资深 Swift 代码审查员。
这是一个单作者项目，没有人工 review——你的审查就是唯一的外部视角。

请针对下面的 diff 重点审查（按重要性排序）：
1. 并发安全：Task.detached / @Observable / 全局可变状态 / 缓存与锁的一致性；
   数据竞争、MainActor 边界错位。
2. 数据安全：文件读写失败是否会破坏原内容；路径拼接、URL 解析、转义问题；
   会话恢复（SessionStore bookmark 保存/加载对称性）。
3. 强制解包 / 强转 / try!：是否引入新的 force_unwrapping / force_cast / force_try。
4. 逻辑正确性：边界条件、空输入、Unicode/换行归一化、异步时序（写入后立刻读等）。
5. 测试：改动是否缺测试；已有测试能否捕获该 bug。

输出格式：按严重程度分级列出问题——[Critical] / [Warning] / [Nit]，每条给出
文件:行号、问题描述、修复建议。没有问题时明确说"未发现问题"。
EOF
echo "===== DIFF START =====" >> "$PROMPT_FILE"
echo "$DIFF" >> "$PROMPT_FILE"
echo "===== DIFF END =====" >> "$PROMPT_FILE"

if [[ $PIPE_CLAUDE -eq 1 ]] && command -v claude &>/dev/null; then
  echo "    -> 交给 claude CLI 审查中..."
  claude -p "$(cat "$PROMPT_FILE")"
  rm -f "$PROMPT_FILE"
else
  echo "    -> claude CLI 不可用（或 --no-pipe），审查提示词已生成，请手动使用："
  echo "       claude -p \"\$(cat \"$PROMPT_FILE\")\""
fi
