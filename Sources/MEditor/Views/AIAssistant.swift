import SwiftUI

/// Reports the transcript's bottom-marker offset within the scroll viewport,
/// used to decide whether to auto-follow streaming output.
private struct AIBottomOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct AISuggestion: Identifiable {
    let id = UUID()
    let icon: String
    let titleKey: String
    let tint: Color
    var promptKey: String? = nil
}

// MARK: - Chat / input panel

/// 浮现于编辑器上方的 AI 助手面板。
/// 支持多 provider：OpenAI 兼容接口（远程）或本地 Claude CLI（复用登录态）。
/// 通过 AppSettings 配置 provider；未配置时显示引导界面。
struct AIAssistantPanel: View {
    @Environment(AppState.self) private var state
    let onClose: () -> Void

    @Environment(AppSettings.self) private var settings
    @State private var showHistory = false
    @State private var atBottom = true
    @FocusState private var inputFocused: Bool

    private var theme: PreviewTheme { state.themeStore.current }
    private var accent: AIAccentStyle { AIAccentStyle.current(settings) }
    private var convo: AIConversation { state.aiConversation }

    private static let primarySuggestions: [AISuggestion] = [
        .init(icon: "sparkles", titleKey: "ai.suggest.whatCanYouDo", tint: Color.appAccent, promptKey: "ai.prompt.whatCanYouDo"),
        .init(icon: "text.alignleft", titleKey: "ai.suggest.summarize", tint: AIBrand.blue, promptKey: "ai.prompt.summarize"),
        .init(icon: "lightbulb.fill", titleKey: "ai.suggest.improveClarity", tint: Color(hex: "F59E0B"), promptKey: "ai.prompt.improveClarity"),
        .init(icon: "checkmark.seal.fill", titleKey: "ai.suggest.fixGrammar", tint: Color(hex: "10B981"), promptKey: "ai.prompt.fixGrammar"),
        .init(icon: "globe", titleKey: "ai.suggest.translate", tint: Color(hex: "06B6D4"), promptKey: "ai.prompt.translate"),
        .init(icon: "paintbrush.fill", titleKey: "ai.suggest.styleDocument", tint: AIBrand.pink, promptKey: "ai.prompt.styleDocument")
    ]

    private static let moreSuggestions: [AISuggestion] = [
        .init(icon: "list.bullet.rectangle.fill", titleKey: "ai.suggest.outline", tint: Color(hex: "3B82F6"), promptKey: "ai.prompt.outline"),
        .init(icon: "arrow.down.right.and.arrow.up.left", titleKey: "ai.suggest.shorten", tint: AIBrand.orange, promptKey: "ai.prompt.shorten"),
        .init(icon: "arrow.up.left.and.arrow.down.right", titleKey: "ai.suggest.expand", tint: Color(hex: "3B82F6"), promptKey: "ai.prompt.expand"),
        .init(icon: "tablecells.fill", titleKey: "ai.suggest.toTable", tint: Color(hex: "14B8A6"), promptKey: "ai.prompt.toTable")
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            composerFooter
        }
        .background(theme.editorBackground)
        .onAppear {
            DispatchQueue.main.async { inputFocused = true }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 0) {
            HStack {
                AIHeaderButton(icon: "clock.arrow.circlepath", help: L("ai.history"), theme: theme) {
                    showHistory.toggle()
                }
                .popover(isPresented: $showHistory, arrowEdge: .bottom) {
                    AIHistoryView(convo: convo, theme: theme) { showHistory = false }
                }
                Spacer()
                Button(action: newChat) {
                    HStack(spacing: 5) {
                        Image(systemName: "plus.bubble")
                            .font(.system(size: 11, weight: .semibold))
                        Text(L("ai.newChat"))
                            .font(.system(size: 12.5, weight: .semibold))
                    }
                    .foregroundStyle(theme.craftPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule(style: .continuous).fill(theme.craftHover))
                    .overlay(Capsule().strokeBorder(theme.separator.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help(L("ai.newChat"))
                Spacer()
                AIHeaderButton(icon: "xmark", help: L("common.close"), theme: theme, action: onClose)
            }
            .padding(.horizontal, 12)
            .frame(height: 52)

            // Context-limit warning banner — shown when the conversation is near
            // the model's context window so the user can start a new chat in time.
            if convo.isApproachingContextLimit {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                    Text("Context nearly full — start a new chat to avoid truncation.")
                        .font(.system(size: 11))
                }
                .foregroundStyle(Color(hex: "92400E"))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: "FEF3C7"))
                .transition(.opacity)
            }
        }
        .background(
            theme.editorBackground
                .overlay(alignment: .bottom) { theme.separator.opacity(0.4).frame(height: 1) }
        )
    }

    // MARK: Body

    @ViewBuilder
    private var content: some View {
        if convo.messages.isEmpty {
            suggestionsView
        } else {
            transcriptView
        }
    }

    private var suggestionsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                greeting
                    .padding(.top, 18)
                    .padding(.bottom, 20)

                sectionHeader("ai.section.suggestions")

                ForEach(Self.primarySuggestions) { s in
                    AISuggestionRow(suggestion: s, theme: theme) { apply(s) }
                }

                if convo.showAllSuggestions {
                    ForEach(Self.moreSuggestions) { s in
                        AISuggestionRow(suggestion: s, theme: theme) { apply(s) }
                    }
                } else {
                    showMoreRow
                }

                sectionHeader("ai.section.yourPrompts")
                    .padding(.top, 6)
                AISuggestionRow(
                    suggestion: .init(icon: "plus.circle.fill", titleKey: "ai.createCustomPrompt", tint: theme.craftSecondary),
                    theme: theme
                ) {
                    inputFocused = true
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            DotGridBackground(opacity: theme.isDark ? 0.10 : 0.18)
                .allowsHitTesting(false)
        )
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 12) {
            AIAssistantOrb(size: 44, glow: true)
            VStack(alignment: .leading, spacing: 4) {
                Text(L("ai.greeting"))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.craftPrimary)
                Text(L("ai.greetingSub"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.craftSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
    }

    private var showMoreRow: some View {
        Button {
            withAnimation(DS.Motion.fast) { convo.showAllSuggestions = true }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .foregroundStyle(theme.craftSecondary)
                Text(L("ai.showMore", Self.moreSuggestions.count))
                    .font(.system(size: 13))
                    .foregroundStyle(theme.craftSecondary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var transcriptView: some View {
        GeometryReader { outer in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(convo.messages) { message in
                            if !message.text.isEmpty {
                                bubble(message).id(message.id)
                            }
                        }
                    if convo.isResponding && (convo.messages.last?.text.isEmpty ?? true) {
                        HStack(spacing: 8) {
                            AIAssistantOrb(size: 18, glow: true)
                            Text(L("ai.thinking"))
                                .font(.system(size: 12.5))
                                .foregroundStyle(theme.craftSecondary)
                            TypingDots(color: theme.craftSecondary)
                        }
                    }
                    if !convo.isResponding && convo.messages.last?.role == .assistant {
                        Button(action: regenerate) {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 10.5, weight: .semibold))
                                Text(L("ai.regenerate"))
                                    .font(.system(size: 11.5, weight: .medium))
                            }
                            .foregroundStyle(theme.craftSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .overlay(
                                Capsule().strokeBorder(theme.separator.opacity(0.6), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                    // Bottom anchor — ensures the last line fully clears the
                    // composer and that scroll-to-end reaches the true bottom.
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                        .background(
                            GeometryReader { g in
                                Color.clear.preference(
                                    key: AIBottomOffsetKey.self,
                                    value: g.frame(in: .named("aiScroll")).maxY
                                )
                            }
                        )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 10)
            }
            .coordinateSpace(name: "aiScroll")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onPreferenceChange(AIBottomOffsetKey.self) { maxY in
                // The bottom marker sits within ~1 viewport when the user is at
                // the end; only then do we follow streaming output.
                atBottom = maxY <= outer.size.height + 40
            }
            .onChange(of: convo.messages.count) { _, _ in
                // A new message (send/reply start) always jumps to the bottom.
                scrollToEnd(proxy)
            }
            .onChange(of: convo.messages.last?.text) { _, _ in
                if atBottom { scrollToEnd(proxy) }
            }
            .onAppear {
                DispatchQueue.main.async { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation(DS.Motion.standard) { proxy.scrollTo("bottom", anchor: .bottom) }
    }

    private func bubble(_ message: AIChatMessage) -> some View {
        HStack(alignment: .top, spacing: 9) {
            if message.role == .user {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(.system(size: 13))
                    .foregroundStyle(accent.onFill(theme))
                    .textSelection(.enabled)
                    .lineSpacing(3)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(accent.fill(theme))
                    )
            } else {
                AIAssistantOrb(size: 20, glow: true).padding(.top, 1)
                VStack(alignment: .leading, spacing: 6) {
                    MarkdownText(
                        markdown: message.text,
                        textColor: theme.craftPrimary,
                        secondaryColor: theme.craftSecondary,
                        codeBackground: theme.isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.045),
                        accent: Color.appAccent
                    )
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(theme.isDark ? Color.white.opacity(0.03) : Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(theme.separator.opacity(theme.isDark ? 0.5 : 0.7), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(theme.isDark ? 0.18 : 0.04), radius: 5, x: 0, y: 1)

                    if !convo.isResponding || message.id != convo.messages.last?.id {
                        HStack(spacing: 12) {
                            AIMessageAction(icon: "doc.on.doc", title: L("ai.copy"), theme: theme) {
                                Pasteboard.copy(message.text)
                            }
                            AIMessageAction(icon: "text.insert", title: L("ai.insertToDoc"), theme: theme) {
                                state.insertIntoEditor(message.text)
                            }
                            Spacer()
                        }
                        .padding(.leading, 2)
                    }
                }
            }
        }
    }

    // MARK: Composer

    private var composerFooter: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Primary prompt area — clean, sitting directly on the frosted card.
            TextField(L("ai.inputPlaceholder"), text: Binding(
                get: { convo.input }, set: { convo.input = $0 }
            ), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .lineLimit(1...6)
                .focused($inputFocused)
                .onSubmit(send)
                .padding(.horizontal, 2)
                .padding(.top, 2)

            // Toolbar row: context chip + attach on the left, send on the right.
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.craftSecondary)
                    Text(documentName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.craftPrimary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule(style: .continuous).fill(theme.craftHover))
                .overlay(Capsule().strokeBorder(theme.separator.opacity(0.4), lineWidth: 0.5))
                .frame(maxWidth: 180, alignment: .leading)

                AICircleButton(icon: "paperclip", theme: theme) { inputFocused = true }

                Spacer(minLength: 4)

                Button(action: { convo.isResponding ? convo.cancelStreaming() : send() }) {
                    HStack(spacing: 5) {
                        if convo.isResponding {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text(L("ai.stop"))
                                .font(.system(size: 12.5, weight: .semibold))
                        } else {
                            Text(L("ai.execute"))
                                .font(.system(size: 12.5, weight: .semibold))
                            Image(systemName: "arrow.up")
                                .font(.system(size: 11, weight: .bold))
                        }
                    }
                    .foregroundStyle(convo.isResponding ? Color.white : (canSend ? accent.onFill(theme) : Color.white.opacity(0.9)))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .background(
                        Capsule(style: .continuous)
                            .fill(convo.isResponding
                                  ? AnyShapeStyle(Color(hex: "EF4444"))
                                  : (canSend ? AnyShapeStyle(accent.fill(theme))
                                             : AnyShapeStyle(Color.gray.opacity(0.32))))
                    )
                    .shadow(color: accent.fill(theme).opacity(canSend && !convo.isResponding ? 0.28 : 0), radius: 7, x: 0, y: 3)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!canSend && !convo.isResponding)
                .animation(DS.Motion.fast, value: canSend)
                .animation(DS.Motion.fast, value: convo.isResponding)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                // Solid white "glass" — visually equal to the prior material+tint
                // but far cheaper to composite while the hero panel scales.
                .fill(theme.isDark ? Color.white.opacity(0.08) : Color.white)
                // Thin top-lit glass hairline.
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: theme.isDark
                                    ? [Color.white.opacity(0.22), Color.white.opacity(0.05)]
                                    : [Color.white.opacity(0.85), Color.white.opacity(0.30)],
                                startPoint: .top, endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                        .blendMode(.plusLighter)
                )
                // Focus accent ring (thin).
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(accent.fill(theme).opacity(inputFocused ? 0.5 : 0), lineWidth: 1)
                )
                // Tight, soft shadow — no wide grey halo.
                .shadow(color: .black.opacity(theme.isDark ? 0.24 : 0.06), radius: 6, x: 0, y: 2)
        )
        .animation(DS.Motion.fast, value: inputFocused)
        .padding(12)
        .background(composerTray)
    }

    /// Opaque strip the glass card floats on. It MUST be opaque so scrolling
    /// transcript content cannot bleed through behind the input (a translucent
    /// material here made the content look clipped/incomplete). The frosted-glass
    /// look lives on the input card itself, above this strip.
    private var composerTray: some View {
        theme.editorBackground
            .overlay(alignment: .top) {
                theme.separator.opacity(0.4).frame(height: 0.5)
            }
            .overlay(alignment: .top) {
                Color.white.opacity(theme.isDark ? 0.05 : 0.55)
                    .frame(height: 1)
                    .padding(.top, 0.5)
                    .blendMode(.plusLighter)
            }
    }

    // MARK: Logic

    private var documentName: String {
        state.selectedTab?.name ?? L("ai.currentDocument")
    }

    private var canSend: Bool {
        !convo.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !convo.isResponding
    }

    private func apply(_ suggestion: AISuggestion) {
        convo.input = L(suggestion.promptKey ?? suggestion.titleKey)
        inputFocused = true
    }

    private func newChat() {
        withAnimation(DS.Motion.fast) {
            convo.newSession()
            convo.showAllSuggestions = false
        }
        inputFocused = true
    }

    private func send() {
        let trimmed = convo.input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !convo.isResponding else { return }

        withAnimation(DS.Motion.standard) {
            convo.messages.append(AIChatMessage(role: .user, text: trimmed))
            convo.input = ""
        }
        convo.persist()
        runCompletion()
    }

    /// Drop the last assistant reply (if any) and re-run the request.
    private func regenerate() {
        guard !convo.isResponding else { return }
        if convo.messages.last?.role == .assistant {
            convo.messages.removeLast()
        }
        runCompletion()
    }

    /// Streams a reply for the current conversation into a fresh assistant bubble.
    private func runCompletion() {
        guard convo.messages.last?.role == .user else { return }
        convo.isResponding = true

        let config = AIConfig.current(settings)
        // Full document context is expensive — inject only on the first user turn.
        // Subsequent turns still carry the full history (including the first turn's
        // context), so the model retains document awareness without re-paying the
        // token cost on every round. Selection context is cheap and always included.
        let userTurnCount = convo.messages.filter { $0.role == .user }.count
        var wire: [AIMessage] = [AIMessage(role: .system, content: systemContext(includeFullDoc: userTurnCount == 1))]
        wire += convo.messages.map {
            AIMessage(role: $0.role == .user ? .user : .assistant, content: $0.text)
        }

        // Capture UUID instead of index so session switches mid-stream don't
        // corrupt a different session's messages.
        let replyMessage = AIChatMessage(role: .assistant, text: "")
        let replyID = replyMessage.id
        convo.messages.append(replyMessage)

        convo.streamTask = Task {
            // Coalesce tokens and flush to the UI at most ~20×/sec, so neither the
            // store (array CoW) nor MarkdownText (full re-parse) runs per token.
            var buffer = ""
            var lastFlush = Date.distantPast
            do {
                for try await chunk in AIClient(config: config).stream(wire) {
                    try Task.checkCancellation()
                    buffer += chunk
                    if Date().timeIntervalSince(lastFlush) > 0.05 {
                        convo.appendToLastMessage(buffer)
                        buffer = ""
                        lastFlush = Date()
                    }
                }
                if !buffer.isEmpty { convo.appendToLastMessage(buffer) }
            } catch is CancellationError {
                if !buffer.isEmpty { convo.appendToLastMessage(buffer) }
                // Remove the empty placeholder only if it's still this session's message.
                if let idx = convo.messages.firstIndex(where: { $0.id == replyID }),
                   convo.messages[idx].text.isEmpty {
                    convo.messages.remove(at: idx)
                }
            } catch {
                if !buffer.isEmpty { convo.appendToLastMessage(buffer) }
                let msg = (error as? AIError)?.errorDescription ?? error.localizedDescription
                if let idx = convo.messages.firstIndex(where: { $0.id == replyID }) {
                    convo.messages[idx].text = "⚠️ " + msg
                }
            }
            convo.isResponding = false
            convo.streamTask = nil
            convo.persist()
        }
    }

    /// System prompt grounding the assistant in the current document.
    ///
    /// - Parameter includeFullDoc: When `true` (first user turn), injects the
    ///   full document body (up to 8 000 chars). On subsequent turns the model
    ///   already has the document in its conversation history, so we only remind
    ///   it of the document name to avoid re-paying the token cost every round.
    ///   Selected text is always included because it's user-initiated and small.
    private func systemContext(includeFullDoc: Bool = true) -> String {
        var ctx = """
You are a helpful writing assistant embedded in a native macOS Markdown editor.
Rules:
- Always format code in fenced code blocks with the correct language tag.
- Use proper Markdown syntax (## headings, **bold**, _italic_, `inline code`).
- When the user asks to insert or rewrite content, output clean Markdown without any preamble like "Here is..." or "Sure!".
- Keep responses focused and concise; avoid repeating the user's request back to them.
"""
        let selection = state.editorSelectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !selection.isEmpty {
            // Selected text is cheap and always relevant — include regardless of turn.
            let sel = selection.count > 4000 ? String(selection.prefix(4000)) + "…" : selection
            let name = state.selectedTab?.name ?? "document"
            ctx += "\n\nThe user selected this text in \"\(name)\":\n\n\(sel)"
        } else if includeFullDoc, let tab = state.selectedTab {
            let body = tab.content.count > 8000 ? String(tab.content.prefix(8000)) + "…" : tab.content
            ctx += "\n\nThe current document is \"\(tab.name)\":\n\n\(body)"
        } else if let tab = state.selectedTab {
            // Subsequent turns: just name — full content is already in conversation history.
            ctx += "\n\nThe user is editing a document named \"\(tab.name)\"."
        }
        let userSkills = state.pluginManager.userSkillsPrompt()
        if !userSkills.isEmpty {
            ctx += "\n\n---\n\n# 用户自定义技能\n\n" + userSkills
        }
        return ctx
    }

    private func sectionHeader(_ key: String) -> some View {
        Text(L(key).uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .kerning(0.6)
            .foregroundStyle(theme.craftSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }
}

// MARK: - Leaf components

private struct AISuggestionRow: View {
    let suggestion: AISuggestion
    let theme: PreviewTheme
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(suggestion.tint.opacity(hovered ? 0.22 : 0.14))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: suggestion.icon)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(suggestion.tint)
                    )
                Text(L(suggestion.titleKey))
                    .font(.system(size: 13))
                    .foregroundStyle(theme.craftPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.craftSecondary.opacity(hovered ? 0.9 : 0))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(hovered ? theme.craftHover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(DS.Motion.micro, value: hovered)
    }
}

private struct AIHistoryView: View {
    @Bindable var convo: AIConversation
    let theme: PreviewTheme
    let onPick: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("ai.history.title"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.craftSecondary)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 6)

            let items = convo.history.filter { !$0.messages.isEmpty }
            if items.isEmpty {
                Text(L("ai.history.empty"))
                    .font(.system(size: 12))
                    .foregroundStyle(theme.craftSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(items) { session in
                            AIHistoryRow(
                                title: session.title.isEmpty ? L("ai.session.untitled") : session.title,
                                isActive: session.id == convo.activeID,
                                theme: theme,
                                onSelect: { convo.activate(session.id); onPick() },
                                onDelete: { convo.delete(session.id) }
                            )
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 8)
                }
                .frame(maxHeight: 320)
            }
        }
        .frame(width: 280)
        .background(theme.editorBackground)
    }
}

private struct AIHistoryRow: View {
    let title: String
    let isActive: Bool
    let theme: PreviewTheme
    let onSelect: () -> Void
    let onDelete: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left")
                .font(.system(size: 11))
                .foregroundStyle(isActive ? Color.appAccent : theme.craftSecondary)
            Text(title)
                .font(.system(size: 12.5))
                .foregroundStyle(theme.craftPrimary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if hovered {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.craftSecondary)
                }
                .buttonStyle(.plain)
                .help(L("common.delete"))
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isActive ? Color.appAccent.opacity(0.12) : (hovered ? theme.craftHover : .clear))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovered = $0 }
    }
}

private struct AIMessageAction: View {
    let icon: String
    let title: String
    let theme: PreviewTheme
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10.5, weight: .medium))
                Text(title).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(hovered ? theme.craftPrimary : theme.craftSecondary)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(title)
    }
}

private struct TypingDots: View {
    let color: Color
    @State private var animating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
                    .offset(y: animating ? -3 : 0)
                    .animation(
                        .easeInOut(duration: 0.45)
                            .repeatForever()
                            .delay(Double(i) * 0.15),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}

private struct AIHeaderButton: View {
    let icon: String
    let help: String
    let theme: PreviewTheme
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.craftSecondary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(hovered ? theme.craftHover : Color.clear))
                .overlay(Circle().strokeBorder(theme.separator.opacity(0.6), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(help)
        .animation(DS.Motion.micro, value: hovered)
    }
}

private struct AICircleButton: View {
    let icon: String
    let theme: PreviewTheme
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.craftSecondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(hovered ? theme.craftHover : Color.clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(DS.Motion.micro, value: hovered)
    }
}
