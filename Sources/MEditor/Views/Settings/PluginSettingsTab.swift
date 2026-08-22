import SwiftUI
import AppKit

// MARK: - Plugins tab

extension SettingsView {
    var pluginsContent: some View {
        let plugins  = state.pluginManager
        let builtins = plugins.skills.filter { $0.source == .builtin }
        let manuals  = plugins.skills.filter { $0.source == .manual }

        return ScrollView {
            VStack(spacing: 0) {
                // ── SKILL.md 解析错误警告条 ──
                if !plugins.loadErrors.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(L("plugin.loadFailed"), systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.orange)
                        ForEach(plugins.loadErrors, id: \.self) { err in
                            Text(err)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DS.Space.lg)
                    .padding(.vertical, DS.Space.sm)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.orange.opacity(0.3), lineWidth: 0.5)
                    )
                    .padding(.horizontal, DS.Space.lg)
                    .padding(.top, DS.Space.md)
                }

                // ── 内置技能 ──
                settingsGroup(title: L("plugin.builtinGroup", builtins.filter(\.isEnabled).count, builtins.count)) {
                    ForEach(builtins) { skill in
                        builtinSkillRow(skill)
                        if skill.id != builtins.last?.id { rowDivider }
                    }
                }

                // ── 我的技能 ──
                settingsGroup(title: L("plugin.myGroup", manuals.filter(\.isEnabled).count)) {
                    if manuals.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "puzzlepiece.extension")
                                .font(.system(size: 24, weight: .light))
                                .foregroundStyle(.tertiary)
                            Text(L("plugin.emptyTitle"))
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)
                            Text(L("plugin.emptyHint"))
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    } else {
                        ForEach(manuals) { skill in
                            skillRow(skill)
                            if skill.id != manuals.last?.id { rowDivider }
                        }
                    }
                }

                HStack {
                    Button {
                        openSkillFilePicker()
                    } label: {
                        Label(L("plugin.add"), systemImage: "plus")
                            .font(.system(size: 13))
                    }
                    Button {
                        Task { await state.pluginManager.reloadAll() }
                    } label: {
                        Label(L("plugin.reload"), systemImage: "arrow.clockwise")
                            .font(.system(size: 13))
                    }
                    .help(L("plugin.reloadHint"))
                    Spacer()
                }
                .padding(.top, 4)

                if let msg = skillAddMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(msg)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.top, 6)
                }

                // ── 技能库 ──
                skillGallerySection
            }
            .padding(DS.Space.lg)
        }
        .onAppear {
            // 初始化已安装状态
            installedSkillIDs = Set(
                CuratedSkillGallery.all
                    .filter { SkillInstaller.isInstalled($0, in: state.pluginManager) }
                    .map(\.id)
            )
        }
    }

    // MARK: - Skill Gallery

    var skillGallerySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.appAccent)
                Text(L("plugin.gallery"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(L("plugin.galleryHint"))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, 4)
            .padding(.top, DS.Space.lg)
            .padding(.bottom, DS.Space.sm)

            // Gallery grid (2-column)
            let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(CuratedSkillGallery.all) { skill in
                    galleryCard(skill)
                }
            }
        }
    }

    func galleryCard(_ skill: GallerySkillDef) -> some View {
        let isInstalled = installedSkillIDs.contains(skill.id)
        let isInstalling = installingSkillID == skill.id

        return VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack(spacing: 8) {
                Image(systemName: skill.icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.appAccent)
                    .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 1) {
                    Text(skill.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                Spacer()
            }

            // Description
            Text(skill.description)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            // Tags
            HStack(spacing: 4) {
                ForEach(skill.tags.prefix(2), id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                        )
                }
                Spacer()
            }

            // Install button
            Button {
                guard !isInstalled, !isInstalling else { return }
                installingSkillID = skill.id
                Task {
                    let result = await SkillInstaller.install(skill, pluginManager: state.pluginManager)
                    switch result {
                    case .installed, .alreadyInstalled:
                        installedSkillIDs.insert(skill.id)
                    case .failed(let err):
                        skillAddMessage = L("plugin.installFailed", err.localizedDescription)
                    }
                    installingSkillID = nil
                }
            } label: {
                HStack(spacing: 4) {
                    if isInstalling {
                        ProgressView().controlSize(.mini)
                    } else if isInstalled {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .medium))
                    } else {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .medium))
                    }
                    Text(isInstalling ? L("plugin.installing") : isInstalled ? L("plugin.installed") : L("plugin.install"))
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isInstalled
                              ? Color.primary.opacity(0.05)
                              : Color.appAccent.opacity(0.12))
                )
                .foregroundStyle(isInstalled ? .secondary : Color.appAccent)
            }
            .buttonStyle(.plain)
            .disabled(isInstalled || isInstalling)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
                )
        )
    }

    /// Row for a built-in skill: toggle + name/desc + "内置" badge (no delete, no path).
    func builtinSkillRow(_ skill: PluginSkill) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle("", isOn: Binding(
                get: { skill.isEnabled },
                set: { state.pluginManager.setEnabled(skill.id, enabled: $0) }
            ))
            .labelsHidden()
            .controlSize(.small)

            VStack(alignment: .leading, spacing: 2) {
                Text(skill.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                if !skill.description.isEmpty {
                    Text(skill.description)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(L("plugin.builtinBadge"))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.07)))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// Row for a manual (user-added) skill: toggle + name/desc/path + delete button.
    func skillRow(_ skill: PluginSkill) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle("", isOn: Binding(
                get: { skill.isEnabled },
                set: { state.pluginManager.setEnabled(skill.id, enabled: $0) }
            ))
            .labelsHidden()
            .controlSize(.small)

            VStack(alignment: .leading, spacing: 2) {
                Text(skill.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                if !skill.description.isEmpty {
                    Text(skill.description)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(skill.skillPath.deletingLastPathComponent().path
                        .replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            // 技能文件操作：在 App 内打开编辑 / Finder 显示 / 移除
            if FileManager.default.fileExists(atPath: skill.skillPath.path) {
                Button {
                    state.openFile(FileItem(url: skill.skillPath, isDirectory: false))
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(L("plugin.openInApp"))

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([skill.skillPath])
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(L("plugin.showInFinder"))
            }

            Button {
                state.pluginManager.remove(id: skill.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(L("plugin.removeSkill"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    func openSkillFilePicker() {
        Task {
            if let url = await state.filePickerService.pickFileOrFolder(title: L("plugin.pickTitle"), allowedExtensions: ["md", "txt"]) {
                let count = state.pluginManager.addSkills(from: url)
                if count > 0 {
                    await state.pluginManager.reloadAll()
                    skillAddMessage = count > 1 ? L("plugin.added", count) : nil
                } else {
                    skillAddMessage = L("plugin.noSkillFound")
                }
            }
        }
    }
}
