import Foundation

enum MessageRole: String, Codable {
    case user
    case assistant
}

/// A step the assistant reported while answering (search, page read, etc).
struct ActivityNote: Codable, Equatable {
    var symbol: String
    var text: String
}

struct ChatMessage: Codable, Equatable {
    var id: String = UUID().uuidString
    var role: MessageRole
    var text: String
    var createdAt: Date = Date()
    var isStreaming: Bool = false
    var failed: Bool = false
    var activity: [ActivityNote] = []

    static func user(_ text: String) -> ChatMessage {
        ChatMessage(role: .user, text: text)
    }

    static func assistantPlaceholder() -> ChatMessage {
        ChatMessage(role: .assistant, text: "", isStreaming: true)
    }
}

struct Conversation: Codable, Equatable {
    var id: String = UUID().uuidString
    var title: String = "New chat"
    var messages: [ChatMessage] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var mode: ChatMode = .chat
    var modelID: String = AIModel.default.id

    var preview: String {
        messages.last(where: { !$0.text.isEmpty })?.text
            .replacingOccurrences(of: "\n", with: " ") ?? "No messages yet"
    }

    /// Derives a title from the first user turn, the way the real client does.
    mutating func retitleIfNeeded() {
        guard title == "New chat",
              let first = messages.first(where: { $0.role == .user })?.text else { return }
        let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let words = trimmed.split(separator: " ").prefix(7).joined(separator: " ")
        title = words.count > 48 ? String(words.prefix(48)) + "..." : words
    }
}

/// The Chat / Cowork toggle from the composer.
enum ChatMode: String, Codable, CaseIterable {
    case chat
    case cowork

    var title: String {
        switch self {
        case .chat: return "Chat"
        case .cowork: return "Cowork"
        }
    }

    var hint: String {
        switch self {
        case .chat: return "Answers in the conversation only."
        case .cowork: return "Allowed to read and edit your Notion workspace."
        }
    }
}

struct AIModel: Equatable {
    let id: String
    let name: String
    let effort: String

    var displayName: String { name }

    static let sonnet = AIModel(id: "sonnet-5", name: "Sonnet 5", effort: "High")
    static let opus = AIModel(id: "opus-5", name: "Opus 5", effort: "High")
    static let haiku = AIModel(id: "haiku-4-5", name: "Haiku 4.5", effort: "Fast")

    static let all: [AIModel] = [.sonnet, .opus, .haiku]
    static let `default` = AIModel.sonnet

    static func model(for id: String) -> AIModel {
        all.first(where: { $0.id == id }) ?? .default
    }
}

/// The quick-start chips under the empty-state composer.
struct QuickAction {
    let title: String
    let systemImage: String
    let prompt: String

    static let all: [QuickAction] = [
        QuickAction(title: "Write", systemImage: "pencil", prompt: "Help me write "),
        QuickAction(title: "Learn", systemImage: "graduationcap", prompt: "Explain "),
        QuickAction(title: "Code", systemImage: "chevron.left.forwardslash.chevron.right", prompt: "Write code that "),
        QuickAction(title: "Life stuff", systemImage: "cup.and.saucer", prompt: "Help me plan "),
        QuickAction(title: "Claude's choice", systemImage: "lightbulb", prompt: "Surprise me with something useful about my workspace")
    ]
}

struct NotionPageSummary: Codable, Equatable {
    var id: String
    var title: String
    var icon: String?
    var url: String
    /// Short excerpt shown in workspace search and fed to Cowork mode.
    var snippet: String = ""

    var iconText: String { icon ?? "" }
}

struct NotionSpace: Codable, Equatable {
    var id: String
    var name: String
    var icon: String?
}
