import Foundation

struct DocumentComment: Codable, Equatable, Identifiable {
    let id: UUID
    var text: String
    var createdAt: Date
    var isResolved: Bool

    init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date = Date(),
        isResolved: Bool = false
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.isResolved = isResolved
    }
}

final class DocumentCommentStore {
    static let shared = DocumentCommentStore()

    private let defaults = UserDefaults.standard
    private let key = "MEditor.documentComments.v1"

    private init() {}

    func comments(for url: URL) -> [DocumentComment] {
        allComments()[documentKey(for: url)] ?? []
    }

    func add(_ text: String, for url: URL) -> [DocumentComment] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return comments(for: url) }

        var all = allComments()
        var items = all[documentKey(for: url)] ?? []
        items.insert(DocumentComment(text: trimmed), at: 0)
        all[documentKey(for: url)] = items
        save(all)
        return items
    }

    func delete(_ id: UUID, for url: URL) -> [DocumentComment] {
        var all = allComments()
        var items = all[documentKey(for: url)] ?? []
        items.removeAll { $0.id == id }
        all[documentKey(for: url)] = items
        save(all)
        return items
    }

    func toggleResolved(_ id: UUID, for url: URL) -> [DocumentComment] {
        var all = allComments()
        var items = all[documentKey(for: url)] ?? []
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].isResolved.toggle()
        }
        all[documentKey(for: url)] = items
        save(all)
        return items
    }

    private func documentKey(for url: URL) -> String {
        url.standardizedFileURL.path
    }

    private func allComments() -> [String: [DocumentComment]] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: [DocumentComment]].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func save(_ comments: [String: [DocumentComment]]) {
        guard let data = try? JSONEncoder().encode(comments) else { return }
        defaults.set(data, forKey: key)
    }
}
