import XCTest
@testable import MEditor

/// PatchEngine 是 agent 写文档的核心纯函数（三级降级匹配：字面 → 统一换行 → 去行尾空白）。
/// 这里的用例按"数据损坏风险最高"的标准覆盖：精确替换、锚点缺失、多处歧义、
/// 边界位置、Unicode、CRLF/行尾空白归一化、连续 patch。
final class AgentPatchEngineTests: XCTestCase {

    // MARK: - 字面精确匹配

    func testApply_exactMatch_replacesOnce() {
        let (updated, count) = PatchEngine.apply(
            to: "hello world, goodbye world",
            find: "hello world",
            replace: "hello Swift",
            all: false
        )
        XCTAssertEqual(updated, "hello Swift, goodbye world")
        XCTAssertEqual(count, 1)
    }

    func testApply_singleOccurrence_allTrue_replacesIt() {
        let (updated, count) = PatchEngine.apply(
            to: "alpha beta gamma",
            find: "beta",
            replace: "BETA",
            all: true
        )
        XCTAssertEqual(updated, "alpha BETA gamma")
        XCTAssertEqual(count, 1)
    }

    func testApply_multilineBlock_exactMatch() {
        let doc = "# Title\n\nold line 1\nold line 2\n\nafter\n"
        let (updated, count) = PatchEngine.apply(
            to: doc,
            find: "old line 1\nold line 2",
            replace: "new line",
            all: false
        )
        XCTAssertEqual(updated, "# Title\n\nnew line\n\nafter\n")
        XCTAssertEqual(count, 1)
    }

    // MARK: - 锚点缺失（PatchNotFoundError 的上游：count == 0）

    func testApply_notFound_returnsOriginalAndZero() {
        let doc = "some content here"
        let (updated, count) = PatchEngine.apply(
            to: doc, find: "missing anchor", replace: "x", all: false)
        XCTAssertEqual(updated, doc, "未找到时原文必须原样返回，不得改动")
        XCTAssertEqual(count, 0)
    }

    func testApply_notFound_allTrue_returnsOriginalAndZero() {
        let doc = "some content here"
        let (updated, count) = PatchEngine.apply(
            to: doc, find: "missing anchor", replace: "x", all: true)
        XCTAssertEqual(updated, doc)
        XCTAssertEqual(count, 0)
    }

    // MARK: - 多处出现的歧义处理

    func testApply_multipleOccurrences_allFalse_replacesFirstOnly() {
        let (updated, count) = PatchEngine.apply(
            to: "foo bar foo baz foo",
            find: "foo",
            replace: "X",
            all: false
        )
        XCTAssertEqual(updated, "X bar foo baz foo", "all=false 只替换第一处")
        XCTAssertEqual(count, 1)
    }

    func testApply_multipleOccurrences_allTrue_replacesAllWithCount() {
        let (updated, count) = PatchEngine.apply(
            to: "foo bar foo baz foo",
            find: "foo",
            replace: "X",
            all: true
        )
        XCTAssertEqual(updated, "X bar X baz X")
        XCTAssertEqual(count, 3)
    }

    func testApply_overlappingNeedle_countsNonOverlappingOccurrences() {
        // "aa" 在 "aaaa" 中非重叠出现 2 次
        let (updated, count) = PatchEngine.apply(
            to: "aaaa", find: "aa", replace: "b", all: true)
        XCTAssertEqual(updated, "bb")
        XCTAssertEqual(count, 2)
    }

    // MARK: - 边界：空文档 / 文首 / 文末 / 全文替换 / 空值

    func testApply_emptyDocument_returnsZero() {
        let (updated, count) = PatchEngine.apply(
            to: "", find: "anything", replace: "x", all: false)
        XCTAssertEqual(updated, "")
        XCTAssertEqual(count, 0)
    }

    func testApply_emptyFind_neverMatches() {
        // 空 find 不得产生插入式替换（range(of:"") 为 nil，replace 原样返回）
        let doc = "abc"
        let single = PatchEngine.apply(to: doc, find: "", replace: "X", all: false)
        XCTAssertEqual(single.updated, doc)
        XCTAssertEqual(single.count, 0)
        let all = PatchEngine.apply(to: doc, find: "", replace: "X", all: true)
        XCTAssertEqual(all.updated, doc)
        XCTAssertEqual(all.count, 0)
    }

    func testApply_atDocumentStart() {
        let (updated, count) = PatchEngine.apply(
            to: "# Heading\nbody", find: "# Heading", replace: "# New Title", all: false)
        XCTAssertEqual(updated, "# New Title\nbody")
        XCTAssertEqual(count, 1)
    }

    func testApply_atDocumentEnd_noTrailingNewline() {
        let (updated, count) = PatchEngine.apply(
            to: "body\ntail", find: "tail", replace: "end", all: false)
        XCTAssertEqual(updated, "body\nend")
        XCTAssertEqual(count, 1)
    }

    func testApply_wholeDocumentReplaced() {
        let (updated, count) = PatchEngine.apply(
            to: "everything", find: "everything", replace: "nothing", all: false)
        XCTAssertEqual(updated, "nothing")
        XCTAssertEqual(count, 1)
    }

    func testApply_emptyReplace_deletesAnchor() {
        let (updated, count) = PatchEngine.apply(
            to: "keep this\nDELETE ME\nkeep that", find: "DELETE ME\n", replace: "", all: false)
        XCTAssertEqual(updated, "keep this\nkeep that")
        XCTAssertEqual(count, 1)
    }

    // MARK: - 特殊字符 / Unicode

    func testApply_regexMetacharacters_treatedLiterally() {
        // 含正则元字符的锚点必须按字面匹配（实现用 .literal，不允许被当正则解释）
        let doc = "price: $100 (USD) [note] *.* file.swift"
        let (updated, count) = PatchEngine.apply(
            to: doc, find: "$100 (USD) [note]", replace: "€90", all: false)
        XCTAssertEqual(updated, "price: €90 *.* file.swift")
        XCTAssertEqual(count, 1)
    }

    func testApply_dotStarAnchor_doesNotActAsWildcard() {
        // "a.c" 字面匹配不得命中 "abc"
        let doc = "abc axc a.c"
        let (updated, count) = PatchEngine.apply(
            to: doc, find: "a.c", replace: "HIT", all: false)
        XCTAssertEqual(updated, "abc axc HIT")
        XCTAssertEqual(count, 1)
    }

    func testApply_emoji_roundtrip() {
        let doc = "status: 🔴 broken\nfixed: no"
        let (updated, count) = PatchEngine.apply(
            to: doc, find: "🔴 broken", replace: "🟢 works 👍", all: false)
        XCTAssertEqual(updated, "status: 🟢 works 👍\nfixed: no")
        XCTAssertEqual(count, 1)
    }

    func testApply_cjk_roundtrip() {
        let doc = "# 标题\n\n这是第一段。\n这是第二段。\n"
        let (updated, count) = PatchEngine.apply(
            to: doc, find: "这是第一段。", replace: "这是改写后的第一段。", all: false)
        XCTAssertEqual(updated, "# 标题\n\n这是改写后的第一段。\n这是第二段。\n")
        XCTAssertEqual(count, 1)
    }

    func testApply_combiningCharacters_matchedExactly() {
        // "é" 的两种 Unicode 表示（U+00E9 与 e+U+0301）不应互相匹配
        let precomposed = "caf\u{E9}"          // café (单一码点)
        let decomposed  = "cafe\u{301}"        // café (组合字符)
        let (updated, count) = PatchEngine.apply(
            to: precomposed, find: decomposed, replace: "x", all: false)
        XCTAssertEqual(updated, precomposed, "不同规范化形式不应误判匹配")
        XCTAssertEqual(count, 0)
    }

    func testApply_replaceTextContainingFindText_allTrue_terminates() {
        // replace 包含 find：一次性替换，不允许无限循环
        let (updated, count) = PatchEngine.apply(
            to: "a a", find: "a", replace: "aa", all: true)
        XCTAssertEqual(updated, "aa aa")
        XCTAssertEqual(count, 2)
    }

    // MARK: - CRLF 行尾（第二级降级：统一换行）

    func testApply_crlfDocument_lfFind_matchesViaNormalization() {
        let doc = "line1\r\nline2\r\nline3"
        let (updated, count) = PatchEngine.apply(
            to: doc, find: "line1\nline2", replace: "merged", all: false)
        XCTAssertEqual(count, 1, "LF find 应通过换行归一化命中 CRLF 文档")
        // 归一化路径的产物是归一化后的文本：换行统一为 LF
        XCTAssertEqual(updated, "merged\nline3")
    }

    func testApply_crlfDocument_singleLineFind_staysLiteral() {
        // find 不跨行时第一级字面匹配即命中，CRLF 原样保留
        let doc = "line1\r\nline2\r\nline3"
        let (updated, count) = PatchEngine.apply(
            to: doc, find: "line2", replace: "two", all: false)
        XCTAssertEqual(updated, "line1\r\ntwo\r\nline3")
        XCTAssertEqual(count, 1)
    }

    func testApply_crlfDocument_crlfFind_literalMatch() {
        let doc = "line1\r\nline2\r\nline3"
        let (updated, count) = PatchEngine.apply(
            to: doc, find: "line1\r\nline2", replace: "merged", all: false)
        XCTAssertEqual(updated, "merged\r\nline3")
        XCTAssertEqual(count, 1)
    }

    // MARK: - 行尾空白（第三级降级：去行尾空白）

    func testApply_trailingWhitespaceInDocument_matchesViaNormalization() {
        // 文档行尾有多余空格，find 没有：第三级降级命中
        let doc = "alpha   \nbeta"
        let (updated, count) = PatchEngine.apply(
            to: doc, find: "alpha\nbeta", replace: "gamma", all: false)
        XCTAssertEqual(count, 1)
        // 归一化路径的产物是归一化后的全文（行尾空白被清理）
        XCTAssertEqual(updated, "gamma")
    }

    func testApply_trailingWhitespaceInFind_matchesCleanDocument() {
        let doc = "alpha\nbeta"
        let (updated, count) = PatchEngine.apply(
            to: doc, find: "alpha  \nbeta", replace: "gamma", all: false)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(updated, "gamma")
    }

    // MARK: - normalizeWSLines

    func testNormalizeWSLines_stripsTrailingSpacesAndTabs() {
        let input = "a   \nb\t\t\nc \t \nend"
        XCTAssertEqual(PatchEngine.normalizeWSLines(input), "a\nb\nc\nend")
    }

    func testNormalizeWSLines_unifiesCRLF() {
        XCTAssertEqual(PatchEngine.normalizeWSLines("a\r\nb\r\nc"), "a\nb\nc")
    }

    func testNormalizeWSLines_keepsLeadingWhitespace() {
        let input = "  indented\n\ttabbed"
        XCTAssertEqual(PatchEngine.normalizeWSLines(input), input)
    }

    // MARK: - 连续多个 patch 顺序应用（agent 多步写文档的真实场景）

    func testSequentialPatches_eachSeesPreviousResult() {
        var doc = "# Doc\n\nintro text\n\nsection one\n\nsection two\n"

        let p1 = PatchEngine.apply(to: doc, find: "intro text", replace: "updated intro", all: false)
        XCTAssertEqual(p1.count, 1)
        doc = p1.updated

        let p2 = PatchEngine.apply(to: doc, find: "section one", replace: "chapter 1", all: false)
        XCTAssertEqual(p2.count, 1)
        doc = p2.updated

        let p3 = PatchEngine.apply(to: doc, find: "section two", replace: "chapter 2", all: false)
        XCTAssertEqual(p3.count, 1)
        doc = p3.updated

        XCTAssertEqual(doc, "# Doc\n\nupdated intro\n\nchapter 1\n\nchapter 2\n")
    }

    func testSequentialPatches_laterPatchAnchorsOnEarlierInsert() {
        // 第二个 patch 的锚点来自第一个 patch 刚写入的内容
        var doc = "start end"
        let p1 = PatchEngine.apply(to: doc, find: "end", replace: "middle end", all: false)
        XCTAssertEqual(p1.count, 1)
        doc = p1.updated

        let p2 = PatchEngine.apply(to: doc, find: "middle", replace: "MIDDLE", all: false)
        XCTAssertEqual(p2.count, 1)
        XCTAssertEqual(p2.updated, "start MIDDLE end")
    }

    func testSequentialPatches_failedMiddlePatch_leavesEarlierChangesIntact() {
        // 模拟 agent 三个 patch 中间失败一个：前面已应用的结果不受影响
        var doc = "aaa bbb ccc"
        let p1 = PatchEngine.apply(to: doc, find: "aaa", replace: "AAA", all: false)
        doc = p1.updated

        let p2 = PatchEngine.apply(to: doc, find: "not there", replace: "x", all: false)
        XCTAssertEqual(p2.count, 0)
        XCTAssertEqual(p2.updated, doc, "失败的 patch 不得改动已应用的内容")

        let p3 = PatchEngine.apply(to: p2.updated, find: "ccc", replace: "CCC", all: false)
        XCTAssertEqual(p3.updated, "AAA bbb CCC")
    }

    // MARK: - nearbyContext（AI 自我纠正的上下文生成）

    func testNearbyContext_findsClosestLineWithLineNumbers() {
        let doc = "one\ntwo\nthree\nfour\nfive\nsix\nseven"
        let ctx = PatchEngine.nearbyContext(in: doc, around: "five")
        XCTAssertTrue(ctx.contains("L4: four"), "应给出命中行前后各 2 行，实际：\(ctx)")
        XCTAssertTrue(ctx.contains("L5: five"))
        XCTAssertTrue(ctx.contains("L6: six"))
        XCTAssertTrue(ctx.contains("L5 附近"))
    }

    func testNearbyContext_matchAtFileStart_clampsWindow() {
        let doc = "first\nsecond\nthird\nfourth\nfifth"
        let ctx = PatchEngine.nearbyContext(in: doc, around: "first")
        XCTAssertTrue(ctx.contains("L1: first"))
        XCTAssertTrue(ctx.contains("L3: third"))
        XCTAssertFalse(ctx.contains("L0"), "行号不得越界到 0，实际：\(ctx)")
    }

    func testNearbyContext_keywordMatchingIsCaseInsensitive() {
        let doc = "Hello World\nother"
        let ctx = PatchEngine.nearbyContext(in: doc, around: "hello")
        XCTAssertTrue(ctx.contains("L1: Hello World"))
    }

    func testNearbyContext_usesFirstNonBlankFindLineAsKeyword() {
        let doc = "alpha\nbeta marker\ngamma"
        let find = "\n\n  \nbeta"
        let ctx = PatchEngine.nearbyContext(in: doc, around: find)
        XCTAssertTrue(ctx.contains("L2: beta marker"), "应跳过 find 开头的空行，实际：\(ctx)")
    }

    func testNearbyContext_noMatch_reportsNotFound() {
        let doc = "alpha\nbeta"
        let ctx = PatchEngine.nearbyContext(in: doc, around: "zzz missing")
        XCTAssertTrue(ctx.contains("未找到"), "实际：\(ctx)")
        XCTAssertTrue(ctx.contains("read_document"), "应提示重新读取文档，实际：\(ctx)")
    }

    func testNearbyContext_emptyFind_returnsPlaceholder() {
        let ctx = PatchEngine.nearbyContext(in: "some doc", around: "")
        XCTAssertTrue(ctx.contains("find 文本为空"), "实际：\(ctx)")
    }

    func testNearbyContext_whitespaceOnlyFind_returnsPlaceholder() {
        let ctx = PatchEngine.nearbyContext(in: "some doc", around: "   \n  ")
        XCTAssertTrue(ctx.contains("find 文本为空"), "实际：\(ctx)")
    }
}
