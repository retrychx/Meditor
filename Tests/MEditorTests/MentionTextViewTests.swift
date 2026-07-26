import XCTest
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
}
