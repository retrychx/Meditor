import XCTest
import SwiftUI
@testable import MEditor

/// MentionTextView 的 Return 拦截与 IME 组字（marked text）的交互。
/// 回归：组字期间按回车必须交给输入法上屏，不能触发发送（否则拼音未上屏就被发出并清空）。
@MainActor
final class MentionTextViewTests: XCTestCase {

    private func makeComposer(
        onSubmit: @escaping () -> Void
    ) -> (AtMentionComposerView.Coordinator, MentionTextView) {
        let coordinator = AtMentionComposerView.Coordinator(
            plainText: .constant(""),
            mentionTokens: .constant([]),
            isFocused: .constant(true),
            onSubmit: onSubmit,
            theme: .github,
            fontSize: 13.5
        )
        return (coordinator, coordinator.textView)
    }

    private func returnKeyEvent(shift: Bool = false) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: shift ? [.shift] : [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: shift ? "\r" : "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        )!
    }

    func testReturnWithoutMarkedTextSubmits() {
        var submitted = 0
        let (_, textView) = makeComposer(onSubmit: { submitted += 1 })
        textView.keyDown(with: returnKeyEvent())
        XCTAssertEqual(submitted, 1, "无组字时回车应触发发送")
    }

    func testReturnWithMarkedTextDoesNotSubmit() {
        var submitted = 0
        let (_, textView) = makeComposer(onSubmit: { submitted += 1 })
        // 模拟中文输入法组字：存在 marked text 时回车归输入法消费
        textView.setMarkedText("nihao", selectedRange: NSRange(location: 5, length: 0),
                               replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(textView.hasMarkedText())
        textView.keyDown(with: returnKeyEvent())
        XCTAssertEqual(submitted, 0, "组字期间回车不应触发发送（应交给输入法上屏）")
    }

    func testReturnAfterMarkedTextCommittedSubmits() {
        var submitted = 0
        let (_, textView) = makeComposer(onSubmit: { submitted += 1 })
        textView.setMarkedText("nihao", selectedRange: NSRange(location: 5, length: 0),
                               replacementRange: NSRange(location: NSNotFound, length: 0))
        textView.unmarkText()
        XCTAssertFalse(textView.hasMarkedText())
        textView.keyDown(with: returnKeyEvent())
        XCTAssertEqual(submitted, 1, "组字上屏后回车恢复正常发送")
    }

    // MARK: - mention token 与 chip 同步

    /// 真实 Binding 容器：.constant 会吞掉写入，无法验证 token 重建
    private final class TokenBox {
        var tokens: [AtMentionToken] = []
    }

    private func makeComposerWithTokens() -> (AtMentionComposerView.Coordinator, MentionTextView, TokenBox) {
        let box = TokenBox()
        let coordinator = AtMentionComposerView.Coordinator(
            plainText: .constant(""),
            mentionTokens: Binding(get: { box.tokens }, set: { box.tokens = $0 }),
            isFocused: .constant(true),
            onSubmit: {},
            theme: .github,
            fontSize: 13.5
        )
        return (coordinator, coordinator.textView, box)
    }

    /// 模拟确认 mention：插入 chip 并登记 token（同 confirmMention 的效果）
    @discardableResult
    private func insertChip(into textView: MentionTextView, box: TokenBox, name: String) -> AtMentionToken {
        let token = AtMentionToken(kind: .file(url: URL(fileURLWithPath: "/tmp/\(name)")))
        textView.textStorage?.append(
            NSAttributedString(attachment: MentionAttachment(token: token, theme: .github, fontSize: 13.5))
        )
        box.tokens.append(token)
        return token
    }

    /// 回归：删除 chip 后 mentionTokens 必须同步移除，否则 send() 仍注入该文件内容
    func testDeletingChipRemovesMentionToken() {
        let (coordinator, textView, box) = makeComposerWithTokens()
        let token = insertChip(into: textView, box: box, name: "a.md")
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification))
        XCTAssertEqual(box.tokens, [token], "chip 存在时 token 应保留")

        // 用户删除 chip（attachment 占一个字符位）
        textView.textStorage?.replaceCharacters(in: NSRange(location: 0, length: 1), with: "")
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification))
        XCTAssertTrue(box.tokens.isEmpty, "删除 chip 后 token 列表应同步移除")
    }

    /// 删除前面的 chip 后，剩余 token 应与文本中 chip 顺序一致
    func testDeletingFirstChipPreservesRemainingTokenOrder() {
        let (coordinator, textView, box) = makeComposerWithTokens()
        _ = insertChip(into: textView, box: box, name: "a.md")
        let tokenB = insertChip(into: textView, box: box, name: "b.md")
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification))
        XCTAssertEqual(box.tokens.count, 2)

        // 删除第一个 chip
        textView.textStorage?.replaceCharacters(in: NSRange(location: 0, length: 1), with: "")
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification))
        XCTAssertEqual(box.tokens, [tokenB], "删除首个 chip 后应保留剩余 token 的文本顺序")
    }
}
