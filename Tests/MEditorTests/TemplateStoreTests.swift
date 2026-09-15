import XCTest
@testable import MEditor

/// TemplateStore 删除路径安全：
/// `delete(id:)` 过去直接把调用方传入的 id 拼进路径，`../../x` 可穿越删除任意
/// 可写的 *.md / *.json。
final class TemplateStoreTests: XCTestCase {

    private func makeStore() -> (store: TemplateStore, base: URL) {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("meditor-tpl-\(UUID().uuidString)")
        return (TemplateStore(baseDir: base), base)
    }

    func test_delete_rejectsPathTraversal() throws {
        let (store, base) = makeStore()
        defer { try? FileManager.default.removeItem(at: base) }

        // userDir = base/MEditor/templates；穿越 id 会指向 base/evil.md
        let victim = base.appendingPathComponent("evil.md")
        try "victim".write(to: victim, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try store.delete(id: "../../evil")) { error in
            guard case TemplateStoreError.invalidName = error else {
                return XCTFail("期望 invalidName，实际 \(error)")
            }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: victim.path),
                      "穿越 id 不得删除 userDir 之外的文件")
    }

    func test_delete_removesOwnedUserTemplate() throws {
        let (store, base) = makeStore()
        defer { try? FileManager.default.removeItem(at: base) }

        let template = try store.save(name: "My Template", content: "hi")
        XCTAssertTrue(store.userTemplates().contains { $0.id == template.id })

        try store.delete(id: template.id)
        XCTAssertFalse(store.userTemplates().contains { $0.id == template.id })
    }

    func test_delete_builtinRejected() {
        let (store, base) = makeStore()
        defer { try? FileManager.default.removeItem(at: base) }
        XCTAssertThrowsError(try store.delete(id: "blank")) { error in
            guard case TemplateStoreError.cannotDeleteBuiltin = error else {
                return XCTFail("期望 cannotDeleteBuiltin，实际 \(error)")
            }
        }
    }
}
