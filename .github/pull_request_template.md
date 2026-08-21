## 变更说明

<!-- 用一两句话说明这个 PR 改了什么、为什么。 -->

## 质量检查（单作者项目：CI 是唯一的 review）

- [ ] 本地 `make test`（或 `swift test`）全绿
- [ ] `swiftlint lint` 无 error（新代码无 force cast / force try / force unwrap）
- [ ] 覆盖率门槛通过：`python3 scripts/coverage_gate.py coverage.lcov`（改动涉及新增逻辑时，关注 logic 覆盖率是否明显下降）
- [ ] 已运行 AI 自审：`bash scripts/ai_review.sh`（或手动把 diff 交给 Claude 审查）

## 风险自查（本项目的盲区清单）

- [ ] **并发**：涉及 `Task.detached` / 全局状态 / `@Observable` 时，是否有数据竞争？（`@MainActor` 边界、锁、缓存一致性）
- [ ] **数据安全**：文件读写是否保持"失败不破坏原内容"语义？路径拼接/转义是否有坑？
- [ ] **会话恢复**：涉及 SessionStore / bookmark 时，保存与加载两侧是否对称（沙箱/非沙箱）？
- [ ] **回归测试**：新行为是否有对应测试用例？修复的 bug 是否有回归用例？
