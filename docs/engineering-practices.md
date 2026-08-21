# 工程实践：单作者项目的质量保障

单作者 + 无人工 review 的现实约束下，质量保障靠四条自动化/制度化机制。本文档
说明每条机制是什么、为什么、以及怎么跑。

## 1. CI 硬性闸门（禁止直接推 main）

- GitHub branch protection 已开启（main）：直接 push 会被拒绝，改动必须走 PR。
- 必要检查：Build & Test (macOS 26)、Build (iOS Simulator)、SwiftLint、Coverage Gate。
- 任何检查变红时 main 不可合入——红测试永远进不了 main。
- 紧急修复 main 时：Settings → Branches → 临时关闭 enforceAdmins，修完立即恢复。

## 2. SwiftLint（.swiftlint.yml）

- 策略：**安全规则硬性 error，风格噪音整体禁用**。
  - error：force_cast、force_try、force_unwrapping（opt-in + severity: error）、empty_count。
  - 禁用：identifier_name / line_length / comma / colon 等纯风格规则（历史代码与默认规则冲突，不强行重构）。
- 本地：`swiftlint lint --config .swiftlint.yml Sources`（0 error 为通过，warning 不阻塞）。
- CI：macOS runner 直接下载官方便携版（universal 二进制），无需 brew。

## 3. 覆盖率门槛（scripts/coverage_gate.py）

- 基线（2026-08 实测）：整体 17.4%，非 View 逻辑代码 46.8%。
- 门槛：整体 ≥ 15%、非 View ≥ 40%——挡住大规模无测试代码的合入。
- 本地生成 lcov：

      swift test --enable-code-coverage
      xcrun llvm-profdata merge -o default.profdata .build/**/codecov/*.profraw
      xcrun llvm-cov export .build/**/MEditorPackageTests.xctest/Contents/MacOS/MEditorPackageTests \
          -instr-profile default.profdata --format=lcov > coverage.lcov
      python3 scripts/coverage_gate.py coverage.lcov

- 说明：聚合门槛只挡大回归；单 PR 的增量覆盖靠 #4 的人工/AI 审查补。

## 4. AI 自审（scripts/ai_review.sh）

- 单作者最大的盲区是"写代码的人审查自己的代码"——AI 是成本最低的第二视角。
- 用法：`bash scripts/ai_review.sh`（未提交改动）或 `bash scripts/ai_review.sh origin/main`（PR 范围）。
- 脚本会先把 diff + 项目风险清单（并发/数据安全/会话恢复/强制解包）拼成审查提示词，
  有 claude CLI 时直接交给它，否则打印提示词。
- 审查发现的 Critical 问题必须在本 PR 内修复；历史上有过"全量 review 修复发现
  Critical 并发安全 bug"的记录，说明这类审查确实有效。
