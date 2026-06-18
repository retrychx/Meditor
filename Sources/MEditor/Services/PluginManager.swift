import Foundation
import Observation

@MainActor
@Observable
final class PluginManager {

    // MARK: - State

    var skills: [PluginSkill] = []

    // MARK: - Persistence keys

    private enum Key {
        static let states  = "MEditor.pluginSkillStates"
        static let manual  = "MEditor.pluginManualSkills"
    }

    // MARK: - Manual add / remove

    func addManual(skillMDURL: URL) {
        guard skillMDURL.lastPathComponent == "SKILL.md" else { return }
        let id = stableID(for: skillMDURL)

        guard !skills.contains(where: { $0.id == id }) else { return }

        do {
            let bookmark = try skillMDURL.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            var entries = loadManualEntries()
            entries.append(ManualSkillEntry(id: id, pathBookmark: bookmark, isEnabled: true))
            saveManualEntries(entries)
        } catch {
            if let bookmark = try? skillMDURL.bookmarkData() {
                var entries = loadManualEntries()
                entries.append(ManualSkillEntry(id: id, pathBookmark: bookmark, isEnabled: true))
                saveManualEntries(entries)
            }
        }

        Task { await loadManual(); loadBuiltins() }
    }

    func remove(id: String) {
        guard skills.first(where: { $0.id == id })?.source != .builtin else { return }
        skills.removeAll { $0.id == id }
        var entries = loadManualEntries()
        entries.removeAll { $0.id == id }
        saveManualEntries(entries)
        persistStates()
    }

    func setEnabled(_ id: String, enabled: Bool) {
        guard let idx = skills.firstIndex(where: { $0.id == id }) else { return }
        skills[idx].isEnabled = enabled
        persistStates()

        if skills[idx].source == .manual {
            var entries = loadManualEntries()
            if let entryIdx = entries.firstIndex(where: { $0.id == id }) {
                entries[entryIdx].isEnabled = enabled
                saveManualEntries(entries)
            }
        }
    }

    // MARK: - Prompt injection

    /// 查询某个内置 skill 是否已启用
    func isBuiltinEnabled(_ id: String) -> Bool {
        skills.first { $0.id == id }?.isEnabled ?? true
    }

    /// 返回用户手动添加的已启用 skill 的 prompt（不含内置）
    func userSkillsPrompt() -> String {
        skills
            .filter { $0.source == .manual && $0.isEnabled }
            .compactMap { skill -> String? in
                guard let content = try? String(contentsOf: skill.skillPath, encoding: .utf8) else { return nil }
                return "## User Skill: \(skill.name)\n\n\(content)"
            }
            .joined(separator: "\n\n---\n\n")
    }

    func enabledSkillsPrompt() -> String {
        skills
            .filter { $0.isEnabled }
            .compactMap { skill -> String? in
                if skill.source == .builtin {
                    guard let item = BuiltinSkills.all.first(where: { $0.id == skill.id }) else { return nil }
                    return "## Skill: \(skill.name)\n\n\(item.content)"
                } else {
                    guard let content = try? String(contentsOf: skill.skillPath, encoding: .utf8) else { return nil }
                    return "## Skill: \(skill.name)\n\n\(content)"
                }
            }
            .joined(separator: "\n\n---\n\n")
    }

    // MARK: - Persistence

    func save() { persistStates() }

    func load() {
        Task {
            await loadManual()
            loadBuiltins()
        }
    }

    // MARK: - Private helpers

    private func loadBuiltins() {
        let states = loadStates()
        let builtins = BuiltinSkills.all.map { item in
            PluginSkill(
                id: item.id,
                name: item.name,
                description: item.description,
                skillPath: URL(fileURLWithPath: "/builtin/\(item.id)"),
                isEnabled: states[item.id] ?? true,
                source: .builtin
            )
        }
        // Builtins go first; existing manual skills follow
        skills = builtins + skills.filter { $0.source == .manual }
    }

    private func loadManual() async {
        let states = loadStates()
        var found: [PluginSkill] = []
        for entry in loadManualEntries() {
            if let url = resolveBookmark(entry.pathBookmark) {
                let isEnabled = states[entry.id] ?? entry.isEnabled
                if let skill = await parseSkill(at: url, id: entry.id, isEnabled: isEnabled) {
                    found.append(skill)
                }
            }
        }
        skills = found
    }

    private func parseSkill(at url: URL, id: String, isEnabled: Bool) async -> PluginSkill? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let name = url.deletingLastPathComponent().lastPathComponent
        let description = extractDescription(from: content)
        return PluginSkill(id: id, name: name, description: description,
                           skillPath: url, isEnabled: isEnabled, source: .manual)
    }

    private func extractDescription(from content: String) -> String {
        let lines = content.components(separatedBy: "\n")

        if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            for line in lines.dropFirst() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed == "---" { break }
                if trimmed.lowercased().hasPrefix("description:") {
                    let value = trimmed.dropFirst("description:".count).trimmingCharacters(in: .whitespaces)
                    if !value.isEmpty { return value }
                }
            }
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && !trimmed.hasPrefix("#") && !trimmed.hasPrefix("---") {
                return String(trimmed.prefix(120))
            }
        }
        return ""
    }

    private func stableID(for url: URL) -> String {
        let path = url.standardizedFileURL.path
        var hasher = Hasher()
        hasher.combine(path)
        let value = abs(hasher.finalize())
        return String(value, radix: 16, uppercase: false)
    }

    private func resolveBookmark(_ data: Data) -> URL? {
        var isStale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    // MARK: - UserDefaults I/O

    private func loadStates() -> [String: Bool] {
        guard let data = UserDefaults.standard.data(forKey: Key.states),
              let decoded = try? JSONDecoder().decode([PluginSkillState].self, from: data)
        else { return [:] }
        return Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0.isEnabled) })
    }

    private func persistStates() {
        let states = skills.map { PluginSkillState(id: $0.id, isEnabled: $0.isEnabled) }
        if let data = try? JSONEncoder().encode(states) {
            UserDefaults.standard.set(data, forKey: Key.states)
        }
    }

    private func loadManualEntries() -> [ManualSkillEntry] {
        guard let data = UserDefaults.standard.data(forKey: Key.manual),
              let decoded = try? JSONDecoder().decode([ManualSkillEntry].self, from: data)
        else { return [] }
        return decoded
    }

    private func saveManualEntries(_ entries: [ManualSkillEntry]) {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: Key.manual)
        }
    }
}
