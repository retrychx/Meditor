import AppKit
import XCTest
@testable import MEditor

@MainActor
final class TabAnchorRegistryTests: XCTestCase {

    private func makeWindow() -> NSWindow {
        NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                 styleMask: [.titled], backing: .buffered, defer: false)
    }

    /// tab 条坐标系（toolbar item view）下并排放两个锚点，验证几何命中。
    func testHitByGeometry() {
        let window = makeWindow()
        let strip = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 44))
        window.contentView!.addSubview(strip)
        let anchorA = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 44))
        let anchorB = NSView(frame: NSRect(x: 120, y: 0, width: 160, height: 44))
        strip.addSubview(anchorA)
        strip.addSubview(anchorB)

        let registry = TabAnchorRegistry()
        let idA = UUID()
        let idB = UUID()
        registry.register(anchorA, tabID: idA)
        registry.register(anchorB, tabID: idB)

        XCTAssertEqual(registry.tabID(at: NSPoint(x: 50, y: 22), in: strip, window: window), idA)
        XCTAssertEqual(registry.tabID(at: NSPoint(x: 200, y: 22), in: strip, window: window), idB)
        XCTAssertNil(registry.tabID(at: NSPoint(x: 399, y: 22), in: strip, window: window))
    }

    /// 锚点埋在深层嵌套里（SwiftUI 真实层级）也能命中。
    func testDeeplyNestedAnchor() {
        let window = makeWindow()
        let strip = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 44))
        window.contentView!.addSubview(strip)
        var parent: NSView = strip
        var anchor = NSView()
        for _ in 0..<5 {
            let box = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 44))
            parent.addSubview(box)
            parent = box
        }
        anchor = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 44))
        parent.addSubview(anchor)

        let registry = TabAnchorRegistry()
        let id = UUID()
        registry.register(anchor, tabID: id)

        XCTAssertEqual(registry.tabID(at: NSPoint(x: 10, y: 10), in: strip, window: window), id)
    }

    /// tab 条命中判定（窗口级右键监视器用：命中 tab 条放行给 tab 守卫）。
    func testIsPointInTabStrip() {
        let window = makeWindow()
        let strip = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 44))
        window.contentView!.addSubview(strip)
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 44))
        strip.addSubview(anchor)

        let registry = TabAnchorRegistry()
        registry.register(anchor, tabID: UUID())

        let stripTop = strip.convert(strip.bounds, to: nil)
        let inside = NSPoint(x: stripTop.minX + 50, y: stripTop.midY)
        let outside = NSPoint(x: stripTop.maxX + 50, y: stripTop.midY)
        XCTAssertTrue(registry.isPointInTabStrip(inside, window: window))
        XCTAssertFalse(registry.isPointInTabStrip(outside, window: window))
    }

    /// 其他窗口的锚点不参与判定。
    func testOtherWindowIgnored() {
        let windowA = makeWindow()
        let windowB = makeWindow()
        let strip = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 44))
        windowA.contentView!.addSubview(strip)
        let anchor = NSView(frame: strip.bounds)
        windowB.contentView!.addSubview(anchor)

        let registry = TabAnchorRegistry()
        registry.register(anchor, tabID: UUID())

        XCTAssertNil(registry.tabID(at: NSPoint(x: 10, y: 10), in: strip, window: windowA))
    }

    func testUnregisterRemovesMapping() {
        let window = makeWindow()
        let strip = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 44))
        window.contentView!.addSubview(strip)
        let anchor = NSView(frame: strip.bounds)
        strip.addSubview(anchor)

        let registry = TabAnchorRegistry()
        let id = UUID()
        registry.register(anchor, tabID: id)
        XCTAssertEqual(registry.tabID(at: NSPoint(x: 10, y: 10), in: strip, window: window), id)

        registry.unregister(anchor)
        XCTAssertNil(registry.tabID(at: NSPoint(x: 10, y: 10), in: strip, window: window))
    }
}

@MainActor
final class TabContextMenuTests: XCTestCase {

    func testMenuStructureAndTarget() {
        let state = AppState(historyStore: LocalHistoryStore(baseDir: FileManager.default.temporaryDirectory))
        let tab = EditorTab(url: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).md"), content: "", language: .markdown)
        let target = TabContextMenu.ActionTarget()
        let menu = TabContextMenu.make(tab: tab, state: state, target: target)

        // close / closeOthers / closeAll / sep / showInFinder / sep / saveAsTemplate
        XCTAssertEqual(menu.items.count, 7)
        let actionItems = menu.items.filter { !$0.isSeparatorItem }
        XCTAssertEqual(actionItems.count, 5)
        XCTAssertTrue(actionItems.allSatisfy { $0.target === target })
        XCTAssertTrue(actionItems.allSatisfy { ($0.representedObject as? UUID) == tab.id })
    }

    func testSaveAsTemplateDisabledWithoutSelection() {
        let state = AppState(historyStore: LocalHistoryStore(baseDir: FileManager.default.temporaryDirectory))
        let tab = EditorTab(url: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).md"), content: "", language: .markdown)
        let menu = TabContextMenu.make(tab: tab, state: state, target: TabContextMenu.ActionTarget())
        guard let last = menu.items.last else { return XCTFail("menu empty") }
        XCTAssertFalse(last.isEnabled)   // 无选中 tab 时禁用
    }
}
