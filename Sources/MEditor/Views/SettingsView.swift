import SwiftUI

struct SettingsView: View {
    @State private var settings = AppSettings.shared
    @Environment(AppState.self) private var state
    private let loc = LocalizationManager.shared
    @State private var selectedTab: SettingsTab = .general

    enum SettingsTab: String, CaseIterable {
        case general, editor, sharing

        var label: String {
            switch self {
            case .general: return L("settings.tab.general")
            case .editor:  return L("settings.tab.editor")
            case .sharing: return L("settings.tab.sharing")
            }
        }

        var icon: String {
            switch self {
            case .general: return "slider.horizontal.3"
            case .editor:  return "textformat"
            case .sharing: return "wifi"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // ── Left sidebar navigation ──
            VStack(spacing: 2) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    SettingsNavItem(
                        icon: tab.icon,
                        label: tab.label,
                        isSelected: selectedTab == tab
                    )
                    .onTapGesture { withAnimation(DS.Motion.fast) { selectedTab = tab } }
                }
                Spacer()
            }
            .padding(.top, 16)
            .padding(.horizontal, 10)
            .frame(width: 140)
            .background(Color(nsColor: .windowBackgroundColor), ignoresSafeAreaEdges: .top)

            // Divider
            Divider()

            // ── Right content ──
            Group {
                switch selectedTab {
                case .general: generalContent
                case .editor:  editorContent
                case .sharing: sharingContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .textBackgroundColor), ignoresSafeAreaEdges: .top)
        }
        .frame(width: 520, height: 340)
        .onAppear { styleSettingsWindow() }
    }

    // MARK: - Window styling

    private func styleSettingsWindow() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard let window = NSApp.windows.first(where: {
                $0.title.localizedCaseInsensitiveContains("setting") ||
                $0.title.localizedCaseInsensitiveContains("设置") ||
                ($0.isVisible && $0 !== NSApp.windows.first(where: { $0.title == "MEditor" }))
            }) else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.styleMask.insert(.fullSizeContentView)
        }
    }

    // MARK: - General

    private var generalContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                settingsGroup(title: L("theme.title")) {
                    settingsRow(label: L("theme.title")) {
                        Picker("", selection: Binding(
                            get: { state.themeStore.current },
                            set: { state.themeStore.current = $0 }
                        )) {
                            ForEach(PreviewTheme.allCases, id: \.self) { t in
                                Text(t.displayName).tag(t)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                    }
                }

                settingsGroup(title: L("settings.section.language")) {
                    settingsRow(label: L("settings.language")) {
                        Picker("", selection: languageBinding) {
                            Text(L("lang.system")).tag(AppLanguage.system)
                            Text("English").tag(AppLanguage.english)
                            Text("中文").tag(AppLanguage.chinese)
                        }
                        .labelsHidden()
                        .frame(width: 120)
                    }
                }

                settingsGroup(title: L("settings.section.preview")) {
                    settingsRow(label: L("settings.fontSize")) {
                        HStack(spacing: 8) {
                            Slider(value: fontSizeBinding, in: 10...28, step: 1)
                                .frame(width: 120)
                            Text("\(settings.previewFontSize) px")
                                .font(DS.Font.mono(12))
                                .foregroundStyle(.secondary)
                                .frame(width: 42, alignment: .trailing)
                        }
                    }
                }

                settingsGroup(title: L("settings.section.save")) {
                    settingsRow(label: L("settings.autoSave")) {
                        Toggle("", isOn: $settings.autoSave).labelsHidden()
                    }
                    if settings.autoSave {
                        Divider().padding(.leading, 16)
                        settingsRow(label: L("settings.interval")) {
                            Picker("", selection: $settings.autoSaveInterval) {
                                Text(L("settings.secondsFormat", 10)).tag(10)
                                Text(L("settings.secondsFormat", 30)).tag(30)
                                Text(L("settings.secondsFormat", 60)).tag(60)
                                Text(L("settings.secondsFormat", 120)).tag(120)
                            }
                            .labelsHidden()
                            .frame(width: 90)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Editor

    private var editorContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                settingsGroup(title: L("settings.section.launchLayout")) {
                    settingsRow(label: L("settings.showSidebar")) {
                        Toggle("", isOn: $settings.showSidebarOnLaunch).labelsHidden()
                    }
                    Divider().padding(.leading, 16)
                    settingsRow(label: L("settings.showEditor")) {
                        Toggle("", isOn: $settings.showEditorOnLaunch).labelsHidden()
                    }
                    Divider().padding(.leading, 16)
                    settingsRow(label: L("settings.showPreview")) {
                        Toggle("", isOn: $settings.showPreviewOnLaunch).labelsHidden()
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Sharing

    private var sharingContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                settingsGroup(title: L("settings.section.lanShare")) {
                    settingsRow(label: L("settings.port")) {
                        TextField("", value: $settings.sharePort, format: .number)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 72)
                    }
                    Divider().padding(.leading, 16)
                    HStack {
                        Text(L("settings.portHint"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
            .padding(16)
        }
    }

    // MARK: - Reusable layout helpers

    private func settingsGroup<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .kerning(0.4)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)

            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 1)
            )
        }
        .padding(.bottom, 20)
    }

    private func settingsRow<Content: View>(
        label: String,
        @ViewBuilder control: () -> Content
    ) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
            Spacer()
            control()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    // MARK: - Bindings

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { Double(settings.previewFontSize) },
            set: { settings.previewFontSize = Int($0) }
        )
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { loc.language },
            set: { loc.language = $0 }
        )
    }
}

// MARK: - Settings Nav Item

private struct SettingsNavItem: View {
    let icon: String
    let label: String
    let isSelected: Bool

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .frame(width: 20, alignment: .center)

            Text(label)
                .font(.system(size: 12.5, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(
                    isSelected
                        ? Color.accentColor.opacity(0.12)
                        : isHovered ? Color.primary.opacity(0.06) : Color.clear
                )
                .animation(.easeOut(duration: 0.1), value: isSelected)
                .animation(.easeOut(duration: 0.07), value: isHovered)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}
