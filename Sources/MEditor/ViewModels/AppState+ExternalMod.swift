import Foundation

// MARK: - External file-change detection + auto-save

extension AppState {

    // MARK: - External modification detection

    func recordModDate(for url: URL) {
        externalModDates[url] = fileService.attributes(at: url)?[.modificationDate] as? Date
    }

    func checkExternalModifications() {
        // 属性读取放到后台，避免主线程对每个 tab 同步访问磁盘。
        let snapshot: [(tab: EditorTab, url: URL)] = tabManager.openTabs
            .filter { !$0.isModified }
            .map    { ($0, $0.url) }
        let knownDates = externalModDates          // value copy
        let svc = fileService

        Task.detached(priority: .utility) { [weak self] in
            var updated: [URL: Date] = [:]
            var modifiedURL: URL? = nil

            for (_, url) in snapshot {
                guard let attrs = svc.attributes(at: url),
                      let diskDate = attrs[.modificationDate] as? Date else { continue }
                let known = knownDates[url]
                if let known, diskDate > known {
                    updated[url] = diskDate
                    modifiedURL  = url
                    break   // 一次只弹一个提示
                } else if known == nil {
                    updated[url] = diskDate
                }
            }

            guard !updated.isEmpty else { return }
            await self?.applyExternalModCheck(updated: updated, modifiedURL: modifiedURL, snapshot: snapshot)
        }
    }

    @MainActor
    private func applyExternalModCheck(
        updated: [URL: Date],
        modifiedURL: URL?,
        snapshot: [(tab: EditorTab, url: URL)]
    ) {
        for (url, date) in updated { externalModDates[url] = date }
        guard let url = modifiedURL,
              let tab = snapshot.first(where: { $0.url == url })?.tab,
              tabManager.openTabs.contains(where: { $0.id == tab.id }),
              !tab.isModified   // 就地再检查一次，防止异步间用户已编辑
        else { return }
        silentlyReloadTab(tab, url: url)
    }

    /// 本地无未保存改动的 tab 被外部修改时，直接静默重载（无需打断用户的弹窗）。
    /// 有未保存改动的 tab 在快照阶段已被过滤，永远不会走到这里。
    private func silentlyReloadTab(_ tab: EditorTab, url: URL) {
        let tabID = tab.id
        Task.detached(priority: .userInitiated) { [weak self, svc = fileService] in
            guard let content = try? svc.readFile(at: url) else { return }
            await MainActor.run { [weak self] in
                guard let self,
                      let t = self.tabManager.openTabs.first(where: { $0.id == tabID }),
                      !t.isModified else { return }
                t.content = content; t.isModified = false
                t.contentRevision &+= 1   // 推送到可见编辑器
                self.recordModDate(for: url)
                if self.tabManager.selectedTabID == tabID {
                    self.syncPreviewContent(from: t)
                    self.previewManager.reloadHTML(url: url)
                }
                self.showToast("已从磁盘更新：\(url.lastPathComponent)", icon: "arrow.triangle.2.circlepath")
            }
        }
    }

    // MARK: - Auto-save

    func setupAutoSaveTimer() {
        autoSaveTimer?.invalidate()
        let settings = AppSettings.shared
        guard settings.autoSave else { return }
        // Retain cycle analysis: Timer → closure → [weak self] → AppState. No cycle.
        // AppState.deinit invalidates the timer and removes the observer, so no leak
        // even though AppState's lifetime equals the app's lifetime in practice.
        let timer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(settings.autoSaveInterval), repeats: true
        ) { [weak self] _ in Task { @MainActor in self?.autoSaveModifiedTabs() } }
        autoSaveTimer = timer
        if autoSaveObserver == nil {
            // [weak self] prevents NotificationCenter → closure → AppState cycle.
            // Removed in deinit via NotificationCenter.default.removeObserver.
            autoSaveObserver = NotificationCenter.default.addObserver(
                forName: .autoSaveSettingsChanged, object: nil, queue: .main
            ) { [weak self] _ in Task { @MainActor in self?.setupAutoSaveTimer() } }
        }
    }

    func autoSaveModifiedTabs() {
        for tab in tabManager.openTabs where tab.isModified { saveTab(tab) }
    }

    /// 内容变化后防抖 2 秒再保存，避免每次击键都写磁盘。
    func scheduleDebounceSave() {
        debounceSaveTimer?.invalidate()
        debounceSaveTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.autoSaveModifiedTabs() }
        }
    }
}
