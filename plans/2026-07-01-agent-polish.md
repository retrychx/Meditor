# Agent 体验打磨计划
> 日期：2026-07-01  
> 范围：P0 修复 + 工具结果展开  
> 原则：**不破坏现有 290 个测试**

---

## 改动一：工具结果可展开查看

**文件：** `Sources/MEditor/Views/Agent/AgentStepView.swift`

### 当前问题
`resultSummary()` 硬截断到 80 字 / 单行，无法展开：
```swift
let firstLine = trimmed.components(separatedBy: "\n").first ?? trimmed
return firstLine.count > 80 ? String(firstLine.prefix(80)) + "…" : firstLine
```

### 改法
`AgentStepView` 新增状态：
```swift
@State private var expandedResultID: String? = nil
```

`toolCallView` 的结果行：
- 结果超过 80 字 或 多行时，显示截断 + `chevron.down` 按钮
- 点击展开：显示完整内容，`.font(.system(size: 11, design: .monospaced))`，最大高度 200pt，内部可滚动
- 按钮切换收起/展开，动画用 `DS.Motion.spring`

**注意：** expandedResultID 绑定到 step.id，避免多个 step 互相影响

---

## 改动二：AgentResultPanel 显示 finalText

**文件：** `Sources/MEditor/Views/Agent/AgentStepView.swift`

### 当前问题
`AgentResultPanel` 完成时只有：
```swift
Text("Agent 已完成")
Button("完成") { onDismiss() }
```
`runner.finalText` 的内容从未渲染。

### 改法
在 Steps ScrollView 和底部 footer 之间，插入 finalText 展示区：

```
[Divider]
[AI 图标] + Markdown 风格文字渲染
    runner.finalText 内容（最大 4 行，超出可展开）
[复制] 按钮（右上角）
[Divider]
[完成] 按钮
```

具体：
- 条件：`!runner.isRunning && !runner.finalText.isEmpty`
- 文字用 `Text(runner.finalText)` + `.font(.system(size: 12.5))` + `.lineLimit(expanded ? nil : 4)`
- 右上角 `Button { UIPasteboard / NSPasteboard 复制 }` → 复制成功短暂显示 "✓ 已复制"
- 展开/折叠控制（超过 4 行时显示"展开"）

---

## 改动三：真正的流式输出

### 背景
`RestAgentBackend.complete()` 用 `"stream": false`，`onChunk` 是完成后一次性调用。  
`AIClient` 已有完整 SSE 实现（`openAIStream` / `anthropicStream`），可以复用。

### 方案：给 AgentBackend 加 streaming 变体（协议扩展默认实现）

**文件 1：** `Sources/MEditor/Services/AI/Agent/Backends/AgentBackend.swift`

新增协议方法（带默认实现，不破坏现有 Backend）：
```swift
/// 流式版本：边生成边回调 chunk，工具调用结束后一次性返回完整 response。
/// 默认实现回退到 complete()，不调用 onTextChunk。
func completeStreaming(
    messages: [AgentMessage],
    tools: [any AgentTool],
    onTextChunk: @escaping @Sendable (String) -> Void
) async throws -> AgentCompletionResponse
```

默认实现：
```swift
extension AgentBackend {
    func completeStreaming(...) async throws -> AgentCompletionResponse {
        try await complete(messages: messages, tools: tools)  // 兜底
    }
}
```

**文件 2：** `Sources/MEditor/Services/AI/Agent/Backends/RestAgentBackend.swift`

实现 `completeStreaming`，分两协议：

**OpenAI SSE with tool_calls：**
- `"stream": true`，解析 SSE
- `delta.content` → 调用 `onTextChunk`
- `delta.tool_calls[N]` → 按 index 累积 `{id, name, arguments}`（arguments 是分片 JSON 字符串，需拼接）
- `finish_reason == "tool_calls"` → 组装 `AgentCompletionResponse(toolCalls: accumulated)`
- `finish_reason == "stop"` → 组装 `AgentCompletionResponse(text: accumulatedText)`

**Anthropic SSE with tool_use：**
- 已有 `AIClient.anthropicStream` 可参考
- `event: content_block_start` + `type: tool_use` → 开始累积工具调用
- `event: content_block_delta` + `type: input_json_delta` → 累积 partial JSON
- `event: message_delta` + `stop_reason: tool_use` → 返回工具调用

**文件 3：** `Sources/MEditor/Services/AI/Agent/AgentRunner.swift`

`_run()` 里把 `backend.complete()` 换成 `backend.completeStreaming()`：
```swift
let response = try await backend.completeStreaming(
    messages: messages,
    tools: tools,
    onTextChunk: { [weak self] chunk in
        // 文本 chunk → 追加到当前 thinking step 旁或直接回调 onChunk
        await MainActor.run {
            self?.onChunk?(chunk)
        }
    }
)
```

仅当 `response.toolCalls.isEmpty`（最终文本回合）时 chunk 才有意义；  
工具调用回合的 chunk 被忽略（工具执行期间不会有文字流）。

---

## 执行顺序

```
Step 1  工具结果展开（AgentStepView）          ← 独立，最快
Step 2  AgentResultPanel 显示 finalText         ← 独立
Step 3  AgentBackend 协议新增 completeStreaming  ← 基础
Step 4  RestAgentBackend 实现流式               ← 依赖 Step 3
Step 5  AgentRunner 接入 completeStreaming       ← 依赖 Step 3/4
Step 6  编译验证 + 原有 290 测试全过
```

---

## 验收标准

- [ ] 工具调用结果超过 80 字时显示展开按钮，点击展开显示完整内容
- [ ] AgentResultPanel 完成时显示 AI 最终文字，有复制按钮
- [ ] AI 助手面板发送消息后，文字逐步出现（流式），而不是等待后一次性显示
- [ ] OpenAI / Anthropic 两个 backend 流式均可用
- [ ] ClaudeCLI backend 保持现有行为（兜底非流式）
- [ ] 290 个测试全部通过，无新 error / warning
