import SwiftUI

// MARK: - Composer（输入区 + 引用选段卡片 + mention picker）

extension AIAssistantPanel {
    @ViewBuilder
    var mentionPickerPopoverContent: some View {
        AtMentionPickerView(
            query: mentionQuery,
            theme: state.themeStore.current,
            onSelect: { candidate in
                NotificationCenter.default.post(
                    name: .atMentionConfirmCandidate,
                    object: candidate
                )
                showMentionPicker = false
            },
            onDismiss: {
                showMentionPicker = false
            }
        )
        .environment(state)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    var composerFooter: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 引用选段卡片（来自「问 AI」带入的选区），可一键移除
            if let quoted = state.aiUI.quotedContext, !quoted.isEmpty {
                quotedContextCard(quoted)
            }

            // Primary prompt area — @mention-aware rich composer
            AtMentionComposerWrapper(
                plainText: Binding(get: { convo.input }, set: { convo.input = $0 }),
                mentionTokens: $mentionTokens,
                // FocusState.Binding 不能隐式转 Binding<Bool>，包一层显式桥接
                isFocused: Binding(get: { inputFocused }, set: { inputFocused = $0 }),
                showMentionPicker: $showMentionPicker,
                mentionQuery: $mentionQuery,
                onSubmit: send,
                // Esc 归属：picker 未显示时 Esc 归面板关闭（与 hero overlay 的 onExitCommand 同一语义）。
                // NSTextView 会吞掉 Esc（cancelOperation:），必须由 composer 显式回调上来。
                onEscapeWithoutPicker: onClose,
                theme: theme,
                pickerContent: { mentionPickerPopoverContent }
            )

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
                .lineLimit(1)
                .truncationMode(.middle)

                Spacer(minLength: 4)

                // run 归属另一会话：不误显 Stop（点了会掐断别处的 run），禁用并说明
                let respondingElsewhere = convo.isResponding && !convo.isActiveSessionResponding
                // ⌘Return 冲突规避：确认条挂起期间把快捷键让给确认条的「允许执行」
                let shortcutEnabled = !respondingElsewhere
                    && convo.pendingCommand == nil && convo.pendingWrite == nil

                Button(action: { convo.isResponding ? convo.cancelStreaming() : send() }) {
                    HStack(spacing: 5) {
                        if respondingElsewhere {
                            Image(systemName: "hourglass")
                                .font(.system(size: 11, weight: .bold))
                            Text(L("ai.respondingElsewhere"))
                                .font(.system(size: 12.5, weight: .semibold))
                        } else if convo.isResponding {
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
                    .foregroundStyle(convo.isResponding && !respondingElsewhere ? Color.white : (canSend ? accent.onFill(theme) : Color.white.opacity(0.9)))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .background(
                        Capsule(style: .continuous)
                            .fill(respondingElsewhere
                                  ? AnyShapeStyle(Color.gray.opacity(0.32))
                                  : convo.isResponding
                                  ? AnyShapeStyle(Color(hex: "EF4444"))
                                  : (canSend ? AnyShapeStyle(accent.fill(theme))
                                             : AnyShapeStyle(Color.gray.opacity(0.32))))
                    )
                    .shadow(color: accent.fill(theme).opacity(canSend && !convo.isResponding ? 0.28 : 0), radius: 7, x: 0, y: 3)
                }
                .buttonStyle(.plain)
                .applyCommandReturnShortcut(enabled: shortcutEnabled)
                .disabled(respondingElsewhere || (!canSend && !convo.isResponding))
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

    /// 「问 AI」带入的引用选段卡片：左侧竖线 + 选段摘要 + 移除按钮。
    private func quotedContextCard(_ text: String) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 9, weight: .semibold))
                    Text(L("ai.quotedSelection"))
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(theme.craftSecondary)
                Text(Self.previewText(text))
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.craftPrimary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
            Button {
                withAnimation(DS.Motion.fast) { state.aiUI.quotedContext = nil }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.craftSecondary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help(L("ai.removeQuote"))
        }
        .padding(.leading, 11)
        .padding(.trailing, 10)
        .padding(.vertical, 7)
        .fixedSize(horizontal: false, vertical: true)   // 锁成内容高度，杜绝被拉伸出空白
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.craftHover.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        // 左侧 accent 竖线用 overlay 绘制，不参与 HStack 高度计算（greedy shape 会撑高）
        .overlay(alignment: .leading) {
            Capsule()
                .fill(Color.appAccent.opacity(0.7))
                .frame(width: 3)
                .padding(.vertical, 6)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(theme.separator.opacity(0.35), lineWidth: 0.5)
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// 折叠引用文本里的多余空白/换行，供卡片单段紧凑预览（不影响发送时的原文）。
    private static func previewText(_ raw: String) -> String {
        raw.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private var documentName: String {
        state.selectedTab?.name ?? L("ai.currentDocument")
    }

    private var canSend: Bool {
        !convo.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !convo.isResponding
    }
}

// MARK: - Conditional ⌘Return

private extension View {
    /// 条件挂载 ⌘Return 快捷键：确认条挂起 / run 归属其他会话时让给对应的界面语义。
    @ViewBuilder
    func applyCommandReturnShortcut(enabled: Bool) -> some View {
        if enabled {
            self.keyboardShortcut(.return, modifiers: [.command])
        } else {
            self
        }
    }
}
