import XCTest
@testable import MEditor

/// BuiltinTemplates / TemplateStore.builtins 的结构性校验：
/// 主题 CSS token 完整、模板 id 唯一、必填字段非空、类别与扩展名一致。
/// 不测内容质量。
final class BuiltinTemplatesTests: XCTestCase {

    // MARK: - 主题 CSS

    func testCSS_knownThemeIDs_returnRespectiveCSS() {
        XCTAssertEqual(BuiltinTemplates.css(for: "html-tufte"), BuiltinTemplates.tufteCSS)
        XCTAssertEqual(BuiltinTemplates.css(for: "html-craft"), BuiltinTemplates.craftCSS)
        XCTAssertEqual(BuiltinTemplates.css(for: "html-dark"), BuiltinTemplates.darkCSS)
    }

    func testCSS_unknownID_fallsBackToCraft() {
        XCTAssertEqual(BuiltinTemplates.css(for: "nope"), BuiltinTemplates.craftCSS)
        XCTAssertEqual(BuiltinTemplates.css(for: ""), BuiltinTemplates.craftCSS)
    }

    func testThemeCSS_eachThemeDefinesAllTokens() {
        let tokens = ["--accent", "--bg", "--text", "--font", "--width", "--font-mono"]
        for (name, css) in [("tufte", BuiltinTemplates.tufteCSS),
                            ("craft", BuiltinTemplates.craftCSS),
                            ("dark", BuiltinTemplates.darkCSS)] {
            for token in tokens {
                XCTAssertTrue(css.contains("\(token):"), "\(name) CSS 缺 token \(token)")
            }
        }
    }

    // MARK: - tokenDefaults

    func testTokenDefaults_knownAndFallback() {
        XCTAssertEqual(BuiltinTemplates.tokenDefaults(for: "html-tufte").width,
                       BuiltinTemplates.tufteTokenDefaults.width)
        XCTAssertEqual(BuiltinTemplates.tokenDefaults(for: "html-dark").bg,
                       BuiltinTemplates.darkTokenDefaults.bg)
        XCTAssertEqual(BuiltinTemplates.tokenDefaults(for: "unknown").width,
                       BuiltinTemplates.craftTokenDefaults.width, "未知 id 应回退 craft")
    }

    func testTokenDefaults_colorsAreHexValues() {
        for defaults in [BuiltinTemplates.tufteTokenDefaults,
                         BuiltinTemplates.craftTokenDefaults,
                         BuiltinTemplates.darkTokenDefaults] {
            for color in [defaults.accent, defaults.bg, defaults.text] {
                XCTAssertTrue(color.hasPrefix("#"), "颜色应为 hex 值，实际：\(color)")
            }
            XCTAssertFalse(defaults.font.isEmpty)
            XCTAssertFalse(defaults.width.isEmpty)
            XCTAssertFalse(defaults.fontMono.isEmpty)
        }
    }

    // MARK: - HTML shell 模板

    func testHTMLShellTemplates_wellFormed() {
        for html in [BuiltinTemplates.htmlTufte, BuiltinTemplates.htmlCraft, BuiltinTemplates.htmlDark] {
            XCTAssertTrue(html.contains("<!DOCTYPE html>"))
            XCTAssertTrue(html.contains("<style>"))
            XCTAssertTrue(html.contains("</html>"))
        }
    }

    // MARK: - Markdown 模板

    func testMarkdownTemplates_nonEmpty() {
        for (name, content) in [("meeting", BuiltinTemplates.meeting),
                                ("techDesign", BuiltinTemplates.techDesign),
                                ("weekly", BuiltinTemplates.weekly),
                                ("journal", BuiltinTemplates.journal),
                                ("prd", BuiltinTemplates.prd),
                                ("bugReport", BuiltinTemplates.bugReport),
                                ("readingNotes", BuiltinTemplates.readingNotes),
                                ("releaseNotes", BuiltinTemplates.releaseNotes),
                                ("retrospective", BuiltinTemplates.retrospective)] {
            XCTAssertFalse(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           "\(name) 模板内容为空")
        }
    }

    // MARK: - TemplateStore.builtins 结构

    func testBuiltinTemplateList_idsUnique() {
        let ids = TemplateStore.builtins.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "内置模板 id 不得重复")
    }

    func testBuiltinTemplateList_requiredFieldsNonEmpty() {
        for t in TemplateStore.builtins {
            XCTAssertFalse(t.id.isEmpty, "模板 id 为空")
            XCTAssertFalse(t.name.isEmpty, "\(t.id) name 为空（检查对应 L key 是否登记）")
            XCTAssertFalse(t.description.isEmpty, "\(t.id) description 为空")
            if t.id != "blank" {
                XCTAssertFalse(t.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                               "\(t.id) content 为空")
            }
        }
    }

    func testBuiltinTemplateList_categoryMatchesExtension() {
        for t in TemplateStore.builtins {
            switch t.category {
            case .markdown:
                XCTAssertEqual(t.fileExtension, "md", "\(t.id) 类别/扩展名不一致")
            case .htmlTheme:
                XCTAssertEqual(t.fileExtension, "html", "\(t.id) 类别/扩展名不一致")
                XCTAssertTrue(t.content.contains("<"), "\(t.id) 是 HTML 主题但内容不像 HTML")
            case .user:
                XCTFail("\(t.id) 内置模板不应是 user 类别")
            }
        }
    }

    func testBuiltinTemplateList_fileNameComposedFromID() {
        for t in TemplateStore.builtins {
            XCTAssertEqual(t.fileName, t.id + "." + t.fileExtension)
        }
    }

    func testHTMLThemeTemplates_haveCSSCoverage() {
        // 每个 html-* 主题模板必须能被 css(for:)/tokenDefaults(for:) 覆盖或为整页模板
        let themeIDs = TemplateStore.builtins.filter { $0.category == .htmlTheme }.map(\.id)
        XCTAssertFalse(themeIDs.isEmpty)
        for id in themeIDs where id != "html-doc" {
            // 整页模板（内容自带 <style>）或 token 主题（走 css(for:)）二选一
            let t = TemplateStore.builtins.first { $0.id == id }!
            let isFullPage = t.content.contains("<style>")
            XCTAssertTrue(isFullPage || BuiltinTemplates.css(for: id).contains(":root"),
                          "\(id) 既不是整页模板也没有对应主题 CSS")
        }
    }
}
