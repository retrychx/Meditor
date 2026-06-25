import Foundation

// MARK: - External file-change detection + auto-save

extension AppState {

    // MARK: - External modification detection

    func recordModDate(for url: URL) {
        externalModDates[url] = fileService.attributes(at: url)?[.modificationDate] as? Date
    }

    func checkExternalModifications() {
        for tab in tabManager.openTabs where !tab.isModified {
            let url = tab.url
            guard let attrs = fileService.attributes(at: url),
                  let diskDate = attrs[.modificationDate] as? Date else { continue }
            let known = externalModDates[url]
            if let known, diskDate > known {
                externalModDates[url] = diskDate
                externallyModifiedTab = tab
                showingReloadPrompt = true
                return
            } else if known == nil {
                externalModDates[url] = diskDate
            }
        }
    }

    func reloadExternallyModifiedTab() {
        guard let tab = externallyModifiedTab else { return }
        let url = tab.url, tabID = tab.id
        showingReloadPrompt = false; externallyModifiedTab = nil
        Task.detached(priority: .userInitiated) { [weak self, svc = fileService] in
            guard let content = try? svc.readFile(at: url) else { return }
            await MainActor.run { [weak self] in
                guard let self,
                      let t = self.tabManager.openTabs.first(where: { $0.id == tabID }) else { return }
                t.content = content; t.isModified = false
                self.recordModDate(for: url)
                if self.tabManager.selectedTabID == tabID { self.syncPreviewContent(from: t) }
            }
        }
    }

    func dismissReloadPrompt() {
        if let tab = externallyModifiedTab { recordModDate(for: tab.url) }
        showingReloadPrompt = false; externallyModifiedTab = nil
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
