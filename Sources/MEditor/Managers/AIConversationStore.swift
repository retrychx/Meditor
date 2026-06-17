import Foundation
import Observation

/// Persistent, multi-session conversation state for the AI assistant.
///
/// Owned by `AppState` and injected into the views (not a singleton), so it is
/// testable and consistent with the rest of the app's dependency wiring. Chats
/// survive the panel being recreated, and are persisted to disk (debounced,
/// off-main) so they survive app relaunches.
@MainActor
@Observable
final class AIConversation {

    private var sessions: [AISession] = []
    private(set) var activeID: UUID
    var input: String = ""
    var isResponding = false
    var showAllSuggestions = false

    /// In-flight streaming task, so it can be cancelled (stop / new chat / switch).
    @ObservationIgnored var streamTask: Task<Void, Never>?
    /// Debounced disk-persist work item.
    @ObservationIgnored private var persistWork: DispatchWorkItem?

    private static let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MEditor", isDirectory: true)
        return base.appendingPathComponent("ai-sessions.json")
    }()

    init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let saved = try? JSONDecoder().decode([AISession].self, from: data),
           !saved.isEmpty {
            sessions = saved
            activeID = saved[0].id
        } else {
            let fresh = AISession()
            sessions = [fresh]
            activeID = fresh.id
        }
    }

    // MARK: Active session access

    private var activeIndex: Int { sessions.firstIndex { $0.id == activeID } ?? 0 }

    var messages: [AIChatMessage] {
        get { sessions.indices.contains(activeIndex) ? sessions[activeIndex].messages : [] }
        set {
            guard sessions.indices.contains(activeIndex) else { return }
            sessions[activeIndex].messages = newValue
            sessions[activeIndex].updatedAt = .now
            if sessions[activeIndex].title.isEmpty,
               let firstUser = newValue.first(where: { $0.role == .user }) {
                sessions[activeIndex].title = String(firstUser.text.prefix(40))
            }
        }
    }

    /// History ordered most-recently-updated first.
    var history: [AISession] {
        sessions.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// O(1) in-place append to the last message — avoids copying the whole
    /// sessions array on every streamed token (was the O(n²) hot path).
    func appendToLastMessage(_ chunk: String) {
        let i = activeIndex
        guard sessions.indices.contains(i), !sessions[i].messages.isEmpty else { return }
        sessions[i].messages[sessions[i].messages.count - 1].text += chunk
        sessions[i].updatedAt = .now
    }

    // MARK: Lifecycle

    func cancelStreaming() {
        streamTask?.cancel()
        streamTask = nil
        isResponding = false
        persist()
    }

    /// Start a fresh session. Reuses the current one if it's already empty.
    func newSession() {
        cancelStreaming()
        input = ""
        if sessions.indices.contains(activeIndex), sessions[activeIndex].messages.isEmpty {
            return
        }
        let fresh = AISession()
        sessions.insert(fresh, at: 0)
        activeID = fresh.id
        persist()
    }

    func activate(_ id: UUID) {
        guard sessions.contains(where: { $0.id == id }) else { return }
        cancelStreaming()
        activeID = id
        input = ""
    }

    func delete(_ id: UUID) {
        if id == activeID { cancelStreaming() }
        sessions.removeAll { $0.id == id }
        if sessions.isEmpty {
            let fresh = AISession()
            sessions = [fresh]
            activeID = fresh.id
        } else if !sessions.contains(where: { $0.id == activeID }) {
            activeID = sessions[0].id
        }
        persist()
    }

    // MARK: Persistence

    func persist() {
        // Debounce + encode/write off the main thread (mirrors SessionStore).
        persistWork?.cancel()
        let snapshot = sessions
        let url = Self.fileURL
        let work = DispatchWorkItem {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
        persistWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.4, execute: work)
    }
}
