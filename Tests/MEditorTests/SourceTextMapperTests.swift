import XCTest
@testable import MEditor

/// SourceTextMapper：预览渲染纯文本选区 → Markdown 源码范围。
final class SourceTextMapperTests: XCTestCase {

    private func mapped(_ selection: String, in source: String) -> String? {
        guard let range = SourceTextMapper.sourceRange(ofPlainSelection: selection, in: source) else {
            return nil
        }
        return String(source[range])
    }

    func test_heading_stripsMarker() {
        let src = "## 项目概览\n\n正文"
        XCTAssertEqual(mapped("项目概览", in: src), "项目概览")
    }

    func test_bold_swallowsMarkers() {
        let src = "这是 **加粗文字** 没错"
        // 命中后向两侧吞掉 **，避免替换后留下 orphaned 标记
        XCTAssertEqual(mapped("加粗文字", in: src), "**加粗文字**")
    }

    func test_strikethrough_swallowsMarkers() {
        let src = "这是 ~~删除线~~ 文本"
        XCTAssertEqual(mapped("删除线", in: src), "~~删除线~~")
    }

    func test_inlineCode_swallowsBackticks() {
        let src = "调用 `readFile` 即可"
        XCTAssertEqual(mapped("readFile", in: src), "`readFile`")
    }

    func test_linkText_keepsLinkTarget() {
        // 链接文字命中：只换文字，保留 ](url) 结构
        let src = "见 [文档](https://example.com) 内容"
        XCTAssertEqual(mapped("文档", in: src), "文档")
    }

    func test_listItem_stripsBullet() {
        let src = "- 第一项\n- 第二项"
        XCTAssertEqual(mapped("第一项", in: src), "第一项")
    }

    func test_multiLineListSelection() {
        let src = "- 第一项\n- 第二项\n- 第三项"
        let result = mapped("第一项\n第二项", in: src)
        XCTAssertEqual(result, "第一项\n- 第二项")
    }

    func test_orderedAndTaskList() {
        let src = "1. 有序项\n- [ ] 待办事项"
        XCTAssertEqual(mapped("有序项", in: src), "有序项")
        XCTAssertEqual(mapped("待办事项", in: src), "待办事项")
    }

    func test_blockquote_stripsMarker() {
        let src = "> 定位：预览即文档"
        XCTAssertEqual(mapped("定位：预览即文档", in: src), "定位：预览即文档")
    }

    func test_tableCell_stripsPipes() {
        let src = "| 维度 | 数据 |\n| --- | --- |\n| 测试 | 555 |"
        XCTAssertEqual(mapped("测试", in: src), "测试")
    }

    func test_fenceContent_skipped() {
        let src = "```\n代码内容\n```\n\n正文内容"
        // fence 行本身不进纯文本；fence 内的内容仍按普通文本映射
        XCTAssertEqual(mapped("正文内容", in: src), "正文内容")
    }

    func test_noMatch_returnsNil() {
        let src = "完整的一段文字"
        XCTAssertNil(mapped("不存在的内容", in: src))
    }

    func test_whitespaceNormalized() {
        let src = "第一  段\n\n第二段"
        XCTAssertEqual(mapped("第一 段 第二段", in: src), "第一  段\n\n第二段")
    }

    func test_escapedMarker_literal() {
        let src = "这是 \\* 转义星号"
        XCTAssertEqual(mapped("*", in: src), "*")
    }

    func test_htmlTag_stripped() {
        let src = "这是 <b>加粗</b> 文本"
        XCTAssertEqual(mapped("加粗", in: src), "加粗")
    }
}
