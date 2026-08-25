import XCTest
@testable import MEditor

/// CuratedSkillGallery 的结构性校验：id 唯一且 URL-safe（要当目录名）、必填字段非空、
/// content 带合法 frontmatter。不测内容质量。与 BuiltinSkills 的 id 冲突也要拦住
/// （安装后靠 id/name 判重，撞内置 id 会导致误判已安装）。
final class CuratedSkillGalleryTests: XCTestCase {

    func testAll_idsUnique() {
        let ids = CuratedSkillGallery.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Gallery 技能 id 不得重复")
    }

    func testAll_idsAreURLSafeFolderNames() {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        for skill in CuratedSkillGallery.all {
            XCTAssertEqual(skill.folderName, skill.id, "folderName 应等于 id")
            XCTAssertFalse(skill.id.isEmpty)
            XCTAssertTrue(skill.id.unicodeScalars.allSatisfy(allowed.contains),
                          "\(skill.id) 含不适合做目录名的字符")
        }
    }

    func testAll_requiredFieldsNonEmpty() {
        for skill in CuratedSkillGallery.all {
            XCTAssertFalse(skill.name.trimmingCharacters(in: .whitespaces).isEmpty, "\(skill.id) name 为空")
            XCTAssertFalse(skill.description.trimmingCharacters(in: .whitespaces).isEmpty, "\(skill.id) description 为空")
            XCTAssertFalse(skill.icon.trimmingCharacters(in: .whitespaces).isEmpty, "\(skill.id) icon 为空")
            XCTAssertFalse(skill.tags.isEmpty, "\(skill.id) tags 为空")
            XCTAssertTrue(skill.tags.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty },
                          "\(skill.id) 含空白 tag")
            XCTAssertFalse(skill.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           "\(skill.id) content 为空")
        }
    }

    func testAll_contentHasFrontmatterWithNameAndDescription() {
        // content 直接落盘为 SKILL.md，frontmatter 缺 name/description 会加载失败
        for skill in CuratedSkillGallery.all {
            let trimmed = skill.content.trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertTrue(trimmed.hasPrefix("---"), "\(skill.id) content 应以 frontmatter 开头")
            let lines = trimmed.split(separator: "\n", maxSplits: 30).map(String.init)
            guard let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
                XCTFail("\(skill.id) frontmatter 未闭合")
                continue
            }
            let header = lines[1..<end].joined(separator: "\n")
            XCTAssertTrue(header.contains("name:"), "\(skill.id) frontmatter 缺 name")
            XCTAssertTrue(header.contains("description:"), "\(skill.id) frontmatter 缺 description")
        }
    }

    func testAll_idsDoNotCollideWithBuiltinSkills() {
        let builtinIDs = Set(BuiltinSkills.all.map(\.id))
        for skill in CuratedSkillGallery.all {
            XCTAssertFalse(builtinIDs.contains(skill.id),
                           "\(skill.id) 与内置技能 id 撞车，安装判重会误判")
        }
    }

    // MARK: - SkillInstaller 判重逻辑

    @MainActor
    func testIsInstalled_emptyPluginManager_returnsFalse() {
        let pm = PluginManager()   // 未 reloadAll，skills 为空
        for skill in CuratedSkillGallery.all {
            XCTAssertFalse(SkillInstaller.isInstalled(skill, in: pm),
                           "空 PluginManager 下 \(skill.id) 不应判为已安装")
        }
    }
}
