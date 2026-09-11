import Foundation

/// Conversations are cached on disk so history survives relaunches, which the
/// old-iOS crowd cares about because background eviction is aggressive there.
final class ConversationStore {
    static let shared = ConversationStore()

    static let didChangeNotification = Notification.Name("ConversationStoreDidChange")

    private let queue = DispatchQueue(label: "com.sa1nt.notionclaude.store")
    private let fileURL: URL

    private(set) var conversations: [Conversation] = []

    private init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("conversations.json")
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        conversations = (try? decoder.decode([Conversation].self, from: data)) ?? []
        sort()
    }

    private func sort() {
        conversations.sort { $0.updatedAt > $1.updatedAt }
    }

    private func persist() {
        let snapshot = conversations
        queue.async { [fileURL] in
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(snapshot) else { return }
            try? data.write(to: fileURL, options: .atomic)
        }
        NotificationCenter.default.post(name: ConversationStore.didChangeNotification, object: nil)
    }

    func conversation(withID id: String) -> Conversation? {
        conversations.first(where: { $0.id == id })
    }

    @discardableResult
    func create() -> Conversation {
        let conversation = Conversation(
            mode: AppSettings.shared.mode,
            modelID: AppSettings.shared.selectedModel.id
        )
        conversations.insert(conversation, at: 0)
        persist()
        return conversation
    }

    func save(_ conversation: Conversation) {
        var updated = conversation
        updated.updatedAt = Date()
        updated.retitleIfNeeded()

        if let index = conversations.firstIndex(where: { $0.id == updated.id }) {
            conversations[index] = updated
        } else {
            conversations.append(updated)
        }
        sort()
        persist()
    }

    func delete(id: String) {
        conversations.removeAll { $0.id == id }
        persist()
    }

    func deleteAll() {
        conversations.removeAll()
        persist()
    }

    func search(_ query: String) -> [Conversation] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return conversations }
        return conversations.filter { conversation in
            if conversation.title.lowercased().contains(needle) { return true }
            return conversation.messages.contains { $0.text.lowercased().contains(needle) }
        }
    }

    /// Powers the Reflect screen: conversation counts per day for a window.
    func dailyCounts(days: Int) -> [(date: Date, count: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<days).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let count = conversations.filter { calendar.isDate($0.createdAt, inSameDayAs: day) }.count
            return (day, count)
        }
    }
}
