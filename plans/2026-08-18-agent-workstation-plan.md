# MEditor 开发计划（2026-08-18）

> 依据：`/Users/migor/Downloads/product-market-analysis-2026-08.zh.md` 的评估结论（见下）+ 代码现状整体 check。
> 定位收敛：**macOS 上给技术人写文档的 Agent 工作台**。核心闭环：Agent 改文档 → 预览立即渲染 → 人机迭代。

## 0. 整体 Check 结果（2026-08-18）

| 项 | 状态 |
|---|---|
| macOS 构建 + 测试 | ✅ 686 测试全绿（0.6.7 后 agent 层四轮加固：生命周期/写确认/上下文预算/停滞检测/并行/可观测性） |
| iOS 构建 | ⚠️ 真机构建缺 provisioning profile（签名问题，非代码问题）；模拟器免签名验证代码编译 |
| CI | ✅ build / release / deploy-docs 三条流水线在 |
| README 路线图 | ❌ 过时：iOS 伴侣仍挂 "Later"（实际已交付）；近两周 agent 能力未体现 |
| docs 债务 | ❌ `project-review.md` 仍写"不是 AI 集成工具"，与现状矛盾 |

对分析报告的采信结论：战略判断（wedge、BYOK、不做清单、闭环空位）采纳；数字未核（"29 工具"实为 14）；工时不信（"Pro 定价 2 天"、App Store 与沙盒冲突被忽视）；MCP 定位修正为"留存/转化工具"而非获客。

## 1. 阶段划分

### Phase 0：文档与路线图对齐（先行，半天）
- [ ] README/README.zh 重写：定位一句话收敛为"技术人的 Agent 文档工作台"；路线图按现状重排（iOS 移入已交付；agent 加固能力补入）；功能清单围绕杀手场景写
- [ ] `docs/project-review.md` 等矛盾文档修正或标注过时

### Phase 1：Onboarding 与激活（P0，~1 周）
解决 BYOK 激活杀手。不碰"免费试用端点"（有成本），走零配置路线：
- [ ] 首启引导：无 key 时进入引导流程，默认推荐 ClaudeCLI 后端（复用 Claude Code 登录态）
- [ ] ClaudeCLI 后端打磨：agent 路径补流式输出；XML 协议健壮性（转义已修，补解析回归测试）
- [ ] 首启演示：内置示例文档 + 一键"整理这篇会议记录"脚本化 demo（用 DebugDemoInlineFlow 现有基建产品化）
- [ ] 设置页"连接测试"强化反馈（错误分类文案已有，接入引导）

### Phase 2：WorkspaceIndexService + 全局搜索（P0，~2 周）
基础设施，UI 搜索与 Agent `search_workspace` 共用同一索引：
- [ ] `WorkspaceIndexService`：增量索引（ FileWatcher 已有，接上）、内容索引 + 文件名索引
- [ ] 全局搜索 UI（⌘⇧F）：结果面板、跳转、预览高亮
- [ ] Agent `search_workspace` 切换到索引（保留 grep fallback）
- [ ] QuickOpen 接入同一索引（目前自建文件列举）

### Phase 3：Agent 修改一键回滚（P0 收尾，~1 周）
写确认已上线，补回滚闭环：
- [x] run 级 checkpoint：agent run 首次写文件前自动快照（内存快照，AgentRunCheckpoint；1MB 上限，超限跳过并提示）
- [x] 步骤面板/会话尾部提供"撤销本次运行全部修改"（含用户后续编辑检测，跳过并点名提示）
- [ ] 与写确认 UI 联动（确认条上可查看 diff）

### Phase 4：macOS 系统集成（P1，~2 周）
原生护城河，Electron 对手永久盲区：
- [ ] Spotlight 索引（CSSearchableIndex，文档内容可搜）
- [ ] Quick Look 插件（空格预览渲染效果，复用预览管线）
- [ ] Shortcuts  intents（打开工作区/导出）

### Phase 5：MCP Server（P1，1-2 周）
- [ ] 把 14 个工具以 MCP 暴露，供 Claude Desktop/Cursor 接入
- [ ] 定位：留存/转化（让 Claude Code 用户零成本接入），不做获客预期

### Phase 6：诊断中心与其余（P2）
- [ ] 交付前检查规则引擎（死链/缺图/重复标题/层级跳跃）——本地规则与 Agent 互补
- [ ] Git 状态指示（与 agent git 技能联动）
- [ ] 字体设置、多窗口（顺手项）

### 明确不做
双链笔记、实时协作、插件/主题市场、Vim 模式、放映模板精细化、图标迭代、窗口 chrome 打磨、iOS 新功能（仅维护）、企业流转（GitLab Snippet）、App Store 上架（与 run_command/工作区访问沙盒冲突，除非做功能阉割版）。

## 2. 执行约定

- 每个 Phase 完成标准：实现 + 测试全绿 + 提交推送；UI 改动需本地构建实测
- 大功能用并行 coder 子代理实现，主代理负责集成验证
- 每个 Phase 结束更新本文件的勾选状态
