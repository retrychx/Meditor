import XCTest
@testable import MEditor

/// 选区浮动操作条（InlineEditBar）展示规则测试：出条门控 + 按内容类型的动作分组。
/// 断言枚举结构而非文案（CI 英文 locale）。
final class InlineEditBarPlanTests: XCTestCase {

    // MARK: - 出条门控

    func testShouldShowRejectsEmptyAndWhitespaceOnly() {
        XCTAssertFalse(InlineEditBarPlan.shouldShow(for: ""))
        XCTAssertFalse(InlineEditBarPlan.shouldShow(for: " "))
        XCTAssertFalse(InlineEditBarPlan.shouldShow(for: "\n\n\n"))   // 纯空行
        XCTAssertFalse(InlineEditBarPlan.shouldShow(for: "  \n \t "))
    }

    func testShouldShowRejectsSingleCharacter() {
        XCTAssertFalse(InlineEditBarPlan.shouldShow(for: "a"))
        XCTAssertFalse(InlineEditBarPlan.shouldShow(for: " x "))      // 去首尾空白后仅 1 字符
    }

    func testShouldShowAcceptsTwoOrMoreCharacters() {
        XCTAssertTrue(InlineEditBarPlan.shouldShow(for: "ab"))
        XCTAssertTrue(InlineEditBarPlan.shouldShow(for: "hello world"))
        XCTAssertTrue(InlineEditBarPlan.shouldShow(for: "  hello  ")) // 首尾空白不计入长度
    }

    // MARK: - 默认选区（普通文本）

    func testPlainTextGetsCoreActions() {
        let plan = InlineEditBarPlan.actions(for: "just a normal sentence.")
        XCTAssertEqual(plan.primary, [.rewrite, .expand, .condense, .translate])
        XCTAssertTrue(plan.overflow.isEmpty)
        XCTAssertFalse(plan.primary.contains(.convertToTable))
    }

    // MARK: - 列表选区（转表格不回归）

    func testListSelectionKeepsConvertToTableFirst() {
        let bullet = InlineEditBarPlan.actions(for: "- alpha\n- beta\n- gamma")
        XCTAssertEqual(bullet.primary.first, .convertToTable)
        XCTAssertEqual(bullet.primary, [.convertToTable, .organizeList, .expand, .condense])
        XCTAssertEqual(bullet.overflow, [.rewrite, .translate])
    }

    func testOrderedListSelectionIsListLike() {
        let plan = InlineEditBarPlan.actions(for: "1. alpha\n2. beta")
        XCTAssertTrue(plan.primary.contains(.convertToTable))
    }

    func testSingleListLineIsNotListLike() {
        let plan = InlineEditBarPlan.actions(for: "- only one item")
        XCTAssertFalse(plan.primary.contains(.convertToTable))
    }

    // MARK: - 代码块 / 标题选区

    func testCodeBlockSelection() {
        let plan = InlineEditBarPlan.actions(for: "```swift\nlet a = 1\n```")
        XCTAssertEqual(plan.primary, [.explainCode, .addComments, .condense])
        XCTAssertEqual(plan.overflow, [.rewrite, .translate])
        XCTAssertFalse(plan.primary.contains(.convertToTable))
    }

    func testHeadingSelection() {
        let plan = InlineEditBarPlan.actions(for: "# 章节标题")
        XCTAssertEqual(plan.primary, [.expandSection, .rewrite])
        XCTAssertEqual(plan.overflow, [.expand, .condense, .translate])
        XCTAssertFalse(plan.primary.contains(.convertToTable))
    }

    // MARK: - 结构不变量

    func testPrimaryNeverExceedsFourAndNoDuplicates() {
        let samples = [
            "plain prose here",
            "# heading",
            "```\ncode\n```",
            "- a\n- b\n- c",
            "1. a\n2. b",
        ]
        for sample in samples {
            let plan = InlineEditBarPlan.actions(for: sample)
            XCTAssertLessThanOrEqual(plan.primary.count, 4, "主行超出 4 个：\(sample)")
            XCTAssertEqual(Set(plan.primary).count, plan.primary.count, "主行重复：\(sample)")
            XCTAssertTrue(Set(plan.primary).isDisjoint(with: plan.overflow), "主行与更多重叠：\(sample)")
        }
    }

    func testConvertToTableOnlyForStructuredSelection() {
        XCTAssertFalse(InlineEditBarPlan.actions(for: "plain prose here").primary.contains(.convertToTable))
        XCTAssertFalse(InlineEditBarPlan.actions(for: "plain prose here").overflow.contains(.convertToTable))
        XCTAssertTrue(InlineEditBarPlan.actions(for: "- a\n- b").primary.contains(.convertToTable))
    }
}
