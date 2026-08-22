import AppKit
import XCTest
@testable import MEditor

/// EditorTabBar 崩溃回归测试。
///
/// 线上崩溃（0.8.1，EXC_BAD_INSTRUCTION / SIGILL，Trap Number 6）：
/// EditorTabBar.body 的 ForEach 内容闭包按下标回读 state.openTabs——
/// SwiftUI 做 ForEach diff（尤其右键菜单「关闭其他/关闭全部」一次关多个 tab）
/// 时可能用旧下标重算内容闭包，而 openTabs 已变短，
/// state.openTabs[idx - 1] 越界 → Swift 运行时 trap。
/// 修复：闭包不再按下标读数组，分隔线判定改为查一次性算好的字典。
@MainActor
final class TabSeparatorLogicTests: XCTestCase {

    private func makeTab(_ name: String) -> EditorTab {
        EditorTab(url: URL(fileURLWithPath: "/tmp/\(name)-\(UUID().uuidString).md"),
                  content: "", language: .markdown)
    }

    func testSingleTabNoSeparatorEntries() {
        let tab = makeTab("a")
        let map = EditorTabBar.separatorBefore(tabs: [tab], selectedID: tab.id)
        XCTAssertTrue(map.isEmpty)
    }

    func testEmptyNoEntries() {
        XCTAssertTrue(EditorTabBar.separatorBefore(tabs: [], selectedID: nil).isEmpty)
    }

    func testFirstTabExcluded() {
        let a = makeTab("a"), b = makeTab("b")
        let map = EditorTabBar.separatorBefore(tabs: [a, b], selectedID: a.id)
        XCTAssertNil(map[a.id])                // 首 tab 无前驱，不在表里
        XCTAssertEqual(map[b.id], false)       // 前驱 a 是选中态 → 不画分隔线
    }

    func testPredecessorSelectedMeansNoSeparator() {
        let a = makeTab("a"), b = makeTab("b")
        let map = EditorTabBar.separatorBefore(tabs: [a, b], selectedID: b.id)
        XCTAssertEqual(map[b.id], true)        // 前驱 a 未被选中（选中的是 b 自己）
        // 展示层还会叠加 !isSelected：b 是选中态，最终不画分隔线——与旧逻辑一致
    }

    func testMiddleTabWithUnselectedPredecessor() {
        let a = makeTab("a"), b = makeTab("b"), c = makeTab("c")
        let map = EditorTabBar.separatorBefore(tabs: [a, b, c], selectedID: c.id)
        XCTAssertEqual(map[b.id], true)        // 前驱 a 未选中 → b 画分隔线
        XCTAssertEqual(map[c.id], true)        // 前驱 b 未选中；c 自己选中，展示层叠加 !isSelected 后不画
    }

    /// 与旧实现（idx > 0 && !isSelected && !prevSelected）语义一致：
    /// showLeadingSeparator = (map[tab.id] ?? false) && tab.id != selectedID
    func testSeparatorSemanticsMatchOldLogic() {
        let ids = (0..<6).map { _ in UUID() }
        let tabs = ids.map { EditorTab(url: URL(fileURLWithPath: "/tmp/t-\($0).md"), content: "", language: .markdown) }
        for sel in [ids[0], ids[2], ids[5], UUID()] {   // 含未选中 tab 的 id
            let map = EditorTabBar.separatorBefore(tabs: tabs, selectedID: sel)
            for (idx, tab) in tabs.enumerated() {
                // 旧逻辑
                let prevSelected = idx > 0 && tabs[idx - 1].id == sel
                let isSelected = tab.id == sel
                let old = idx > 0 && !isSelected && !prevSelected
                // 新逻辑
                let new = (map[tab.id] ?? false) && !isSelected
                XCTAssertEqual(new, old, "idx=\(idx) sel=\(sel)")
            }
        }
    }
}

/// 右键菜单 action（关闭/关闭其他/关闭全部）的回归测试：
/// 关闭时 openTabs 被逐个改写，验证 action 内部用快照、不越界、不崩溃。
@MainActor
final class TabContextMenuActionTests: XCTestCase {

    private func makeState(tabCount: Int) -> AppState {
        let state = AppState(historyStore: LocalHistoryStore(baseDir: FileManager.default.temporaryDirectory))
        for i in 0..<tabCount {
            state.openFile(FileItem(url: URL(fileURLWithPath: "/tmp/action-\(UUID().uuidString)-\(i).md"),
                                    isDirectory: false))
        }
        return state
    }

    private func menuItem(for tab: EditorTab, action: Selector, target: AnyObject) -> NSMenuItem {
        let item = NSMenuItem(title: "t", action: action, keyEquivalent: "")
        item.target = target
        item.representedObject = tab.id
        return item
    }

    func testCloseTabAction() {
        let state = makeState(tabCount: 4)
        let coordinator = TabBarRightClickGuard.Coordinator()
        coordinator.state = state
        let closed = state.openTabs[1]
        coordinator.closeTabAction(menuItem(for: closed, action: #selector(TabBarRightClickGuard.Coordinator.closeTabAction(_:)), target: coordinator))
        XCTAssertEqual(state.openTabs.count, 3)
        XCTAssertFalse(state.openTabs.contains { $0.id == closed.id })
    }

    func testCloseOthersAction() {
        let state = makeState(tabCount: 5)
        let coordinator = TabBarRightClickGuard.Coordinator()
        coordinator.state = state
        let kept = state.openTabs[2]
        coordinator.closeOthersAction(menuItem(for: kept, action: #selector(TabBarRightClickGuard.Coordinator.closeOthersAction(_:)), target: coordinator))
        XCTAssertEqual(state.openTabs.map(\.id), [kept.id])
    }

    func testCloseAllAction() {
        let state = makeState(tabCount: 5)
        let coordinator = TabBarRightClickGuard.Coordinator()
        coordinator.state = state
        let any = state.openTabs[0]
        coordinator.closeAllAction(menuItem(for: any, action: #selector(TabBarRightClickGuard.Coordinator.closeAllAction(_:)), target: coordinator))
        XCTAssertTrue(state.openTabs.isEmpty)
    }

    /// 关闭动作在 tab 已被关掉之后再次触发（悬垂菜单项场景）：应安全 no-op。
    func testActionAfterTabAlreadyClosedIsNoOp() {
        let state = makeState(tabCount: 2)
        let coordinator = TabBarRightClickGuard.Coordinator()
        coordinator.state = state
        let tab = state.openTabs[0]
        state.closeTab(tab.id)
        coordinator.closeTabAction(menuItem(for: tab, action: #selector(TabBarRightClickGuard.Coordinator.closeTabAction(_:)), target: coordinator))
        coordinator.closeAllAction(menuItem(for: tab, action: #selector(TabBarRightClickGuard.Coordinator.closeAllAction(_:)), target: coordinator))
        XCTAssertEqual(state.openTabs.count, 1)  // 不崩溃、不改状态
    }

    func testCloseModifiedTabShowsConfirmation() {
        let state = makeState(tabCount: 2)
        let coordinator = TabBarRightClickGuard.Coordinator()
        coordinator.state = state
        let modified = state.openTabs[0]
        modified.isModified = true
        coordinator.closeTabAction(menuItem(for: modified, action: #selector(TabBarRightClickGuard.Coordinator.closeTabAction(_:)), target: coordinator))
        XCTAssertEqual(state.openTabs.count, 2)          // 未直接关闭
        XCTAssertTrue(state.showingCloseConfirmation)    // 进入保存确认
        XCTAssertEqual(state.pendingCloseTab?.id, modified.id)
    }
}
