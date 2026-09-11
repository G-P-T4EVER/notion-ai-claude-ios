import Foundation

enum MessageRole: String, Codable {
    case user
    case assistant
}

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
    var modelID: String?
    var progress: String?

    static func user(_ text: String) -> ChatMessage {
        ChatMessage(role: .user, text: text)
    }

    static func assistantPlaceholder(modelID: String? = nil) -> ChatMessage {
        ChatMessage(
            role: .assistant,
            text: "",
            isStreaming: true,
            modelID: modelID,
            progress: StreamingStatus.initial
        )
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
    var effortRaw: String?
    var skillIDs: [String]?
    var agentID: String?

    var effort: ModelEffort {
        get { ModelEffort(rawValue: effortRaw ?? "") ?? AIModel.model(for: modelID).defaultEffort }
        set { effortRaw = newValue.rawValue }
    }

    var preview: String {
        for message in messages where message.role == .user {
            let text = Markdown.plainText(message.text)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
        }
        for message in messages {
            let text = Markdown.plainText(message.text)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
        }
        return "Empty conversation"
    }

    mutating func retitleIfNeeded() {
        guard title == "New chat" || title.isEmpty else { return }
        guard let first = messages.first(where: { $0.role == .user }) else { return }
        let plain = Markdown.plainText(first.text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plain.isEmpty else { return }
        let words = plain.split(separator: " ").prefix(7).joined(separator: " ")
        title = words.count > 48 ? String(words.prefix(48)) + "…" : words
    }
}

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
        case .chat: return "Ask anything about your workspace"
        case .cowork: return "Let Notion AI edit pages alongside you"
        }
    }
}

// MARK: - Providers

enum ModelProvider: String, Codable, CaseIterable {
    case anthropic
    case openai
    case google
    case xai
    case moonshot
    case auto

    var title: String {
        switch self {
        case .anthropic: return "Anthropic"
        case .openai: return "OpenAI"
        case .google: return "Google"
        case .xai: return "xAI"
        case .moonshot: return "Moonshot AI"
        case .auto: return "Notion AI"
        }
    }
}

enum PlanTier: String, Codable, CaseIterable {
    case free
    case plus
    case business

    var title: String {
        switch self {
        case .free: return "Free"
        case .plus: return "Plus"
        case .business: return "Business"
        }
    }

    var order: Int {
        switch self {
        case .free: return 0
        case .plus: return 1
        case .business: return 2
        }
    }
}

enum ModelEffort: String, Codable, CaseIterable {
    case fast
    case balanced
    case high
    case max

    var title: String {
        switch self {
        case .fast: return "Fast"
        case .balanced: return "Balanced"
        case .high: return "High"
        case .max: return "Max"
        }
    }

    var detail: String {
        switch self {
        case .fast: return "Shortest thinking time"
        case .balanced: return "Everyday default"
        case .high: return "More reasoning, slower"
        case .max: return "Deepest reasoning, slowest"
        }
    }

    var symbol: String {
        switch self {
        case .fast: return "hare"
        case .balanced: return "dial.medium"
        case .high: return "brain"
        case .max: return "sparkles"
        }
    }
}

struct AIModel: Equatable {
    let id: String
    let name: String
    let provider: ModelProvider
    let tier: PlanTier
    let efforts: [ModelEffort]
    let blurb: String

    var displayName: String { name }

    var defaultEffort: ModelEffort {
        if efforts.contains(.balanced) { return .balanced }
        return efforts.first ?? .balanced
    }

    // Kept for older call sites: label shown next to the model name.
    var effort: String { defaultEffort.title }

    var supportsEffort: Bool { efforts.count > 1 }

    static let auto = AIModel(
        id: "auto",
        name: "Auto",
        provider: .auto,
        tier: .free,
        efforts: [.balanced],
        blurb: "Notion picks the best model for each request"
    )

    static let all: [AIModel] = [
        auto,
        AIModel(id: "fable-5-1", name: "Claude Fable 5.1", provider: .anthropic, tier: .plus,
                efforts: [.fast, .balanced, .high, .max], blurb: "Creative long-form writing"),
        AIModel(id: "fable-5-0", name: "Claude Fable 5.0", provider: .anthropic, tier: .plus,
                efforts: [.fast, .balanced, .high], blurb: "Previous Fable generation"),
        AIModel(id: "opus-5", name: "Claude Opus 5", provider: .anthropic, tier: .plus,
                efforts: [.balanced, .high, .max], blurb: "Most capable Claude for hard work"),
        AIModel(id: "opus-4-8", name: "Claude Opus 4.8", provider: .anthropic, tier: .plus,
                efforts: [.balanced, .high, .max], blurb: "Strong reasoning, wide context"),
        AIModel(id: "opus-4-6", name: "Claude Opus 4.6", provider: .anthropic, tier: .business,
                efforts: [.balanced, .high], blurb: "Stable enterprise build"),
        AIModel(id: "sonnet-5", name: "Claude Sonnet 5", provider: .anthropic, tier: .free,
                efforts: [.fast, .balanced, .high], blurb: "Fast everyday Claude"),
        AIModel(id: "gpt-6-astra", name: "ChatGPT 6 Astra", provider: .openai, tier: .plus,
                efforts: [.balanced, .high, .max], blurb: "Flagship OpenAI reasoning"),
        AIModel(id: "gpt-5-6-sol", name: "ChatGPT 5.6 SOL", provider: .openai, tier: .plus,
                efforts: [.fast, .balanced, .high], blurb: "Bright, concise answers"),
        AIModel(id: "gpt-5-6-terra", name: "ChatGPT 5.6 TERRA", provider: .openai, tier: .plus,
                efforts: [.fast, .balanced, .high], blurb: "Grounded, factual tone"),
        AIModel(id: "gpt-5-6-luna", name: "ChatGPT 5.6 LUNA", provider: .openai, tier: .business,
                efforts: [.balanced, .high], blurb: "Careful, low-temperature drafting"),
        AIModel(id: "gpt-5-5-thinking", name: "ChatGPT 5.5-Thinking", provider: .openai, tier: .plus,
                efforts: [.high, .max], blurb: "Extended chain-of-thought"),
        AIModel(id: "grok-4-6", name: "Grok 4.6", provider: .xai, tier: .plus,
                efforts: [.fast, .balanced, .high], blurb: "Fresh web-leaning answers"),
        AIModel(id: "kimi-k3", name: "Kimi K3", provider: .moonshot, tier: .plus,
                efforts: [.balanced, .high], blurb: "Very long document handling"),
        AIModel(id: "gemini-3-7-flash", name: "Gemini 3.7 Flash", provider: .google, tier: .free,
                efforts: [.fast, .balanced], blurb: "Newest fast Gemini"),
        AIModel(id: "gemini-3-6-flash", name: "Gemini 3.6 Flash", provider: .google, tier: .free,
                efforts: [.fast, .balanced], blurb: "Fast and cheap"),
        AIModel(id: "gemini-3-5-flash", name: "Gemini 3.5 Flash", provider: .google, tier: .free,
                efforts: [.fast, .balanced], blurb: "Previous Flash generation"),
        AIModel(id: "gemini-3-1-pro", name: "Gemini 3.1 Pro", provider: .google, tier: .business,
                efforts: [.balanced, .high, .max], blurb: "Long-context Google reasoning")
    ]

    static let `default` = AIModel.all.first(where: { $0.id == "sonnet-5" }) ?? AIModel.auto

    // Legacy aliases.
    static var sonnet: AIModel { model(for: "sonnet-5") }
    static var opus: AIModel { model(for: "opus-5") }
    static var haiku: AIModel { model(for: "gemini-3-7-flash") }

    static func model(for id: String) -> AIModel {
        all.first(where: { $0.id == id }) ?? AIModel.default
    }

    static func models(in tier: PlanTier) -> [AIModel] {
        all.filter { $0.tier == tier }
    }

    static func grouped() -> [(provider: ModelProvider, models: [AIModel])] {
        var result: [(ModelProvider, [AIModel])] = []
        for provider in ModelProvider.allCases {
            let models = all.filter { $0.provider == provider }
            if !models.isEmpty { result.append((provider, models)) }
        }
        return result
    }
}

// MARK: - Greetings

enum Greeting {
    private static let morning = [
        "Good morning", "Morning — what's first?", "Early start", "Fresh page, fresh day",
        "Coffee and context", "Let's set up the day"
    ]

    private static let afternoon = [
        "Good afternoon", "Back at it", "What are we building?", "Mid-day momentum",
        "Pick up where you left off", "Let's make progress"
    ]

    private static let evening = [
        "Good evening", "Winding down?", "Evening session", "One more thing tonight?",
        "Let's wrap something up", "Quiet hours, clear thoughts"
    ]

    private static let night = [
        "Still up?", "Late night ideas", "The workspace never sleeps", "Burning the midnight oil",
        "Quiet o'clock", "Let's keep it short tonight"
    ]

    private static let anytime = [
        "You're here!", "Where should we start?", "What's on your mind?", "Ready when you are",
        "Ask me anything", "Let's dig in", "Something new?", "Your workspace, your questions"
    ]

    static func random(name: String?, date: Date = Date()) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let timed: [String]
        switch hour {
        case 5..<12: timed = morning
        case 12..<18: timed = afternoon
        case 18..<23: timed = evening
        default: timed = night
        }

        var pool = timed + anytime
        if let first = firstName(from: name) {
            pool += timed.map { "\($0), \(first)" }
            pool += ["Hey \(first)", "\(first), what's next?", "Welcome back, \(first)"]
        }
        return pool.randomElement() ?? "You're here!"
    }

    static func firstName(from name: String?) -> String? {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return nil
        }
        let first = name.split(separator: " ").first.map(String.init) ?? name
        return first.count > 24 ? nil : first
    }
}

enum StreamingStatus {
    static let initial = "Thinking…"

    static let stages = [
        "Thinking…",
        "Reading your workspace…",
        "Pulling relevant pages…",
        "Connecting the pieces…",
        "Drafting a response…",
        "Checking the details…",
        "Almost there…"
    ]

    static func stage(at index: Int) -> String {
        stages[min(index, stages.count - 1)]
    }
}

// MARK: - Library types

struct Skill: Codable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var icon: String
    var prompt: String
    var enabled: Bool = true
    var builtIn: Bool = false
}

struct AgentProfile: Codable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var icon: String
    var instructions: String
    var modelID: String = AIModel.default.id
    var effortRaw: String = ModelEffort.balanced.rawValue
    var tone: String = "Neutral"
    var skillIDs: [String] = []
    var connectorIDs: [String] = []
    var createdAt: Date = Date()

    var effort: ModelEffort {
        get { ModelEffort(rawValue: effortRaw) ?? .balanced }
        set { effortRaw = newValue.rawValue }
    }

    var model: AIModel { AIModel.model(for: modelID) }
}

struct MemoryItem: Codable, Equatable {
    var id: String = UUID().uuidString
    var text: String
    var source: String
    var createdAt: Date = Date()
}

struct Connector: Equatable {
    let id: String
    let name: String
    let category: String
    let symbol: String
    let detail: String

    static let all: [Connector] = [
        Connector(id: "slack", name: "Slack", category: "Work", symbol: "number", detail: "Search channels and threads"),
        Connector(id: "google-drive", name: "Google Drive", category: "Work", symbol: "folder", detail: "Docs, Sheets and Slides"),
        Connector(id: "gmail", name: "Gmail", category: "Work", symbol: "envelope", detail: "Read and draft mail"),
        Connector(id: "google-calendar", name: "Google Calendar", category: "Work", symbol: "calendar", detail: "Events and availability"),
        Connector(id: "github", name: "GitHub", category: "Developer", symbol: "chevron.left.forwardslash.chevron.right", detail: "Repos, issues and PRs"),
        Connector(id: "linear", name: "Linear", category: "Developer", symbol: "square.stack.3d.up", detail: "Issues and cycles"),
        Connector(id: "jira", name: "Jira", category: "Developer", symbol: "ladybug", detail: "Tickets and sprints"),
        Connector(id: "figma", name: "Figma", category: "Design", symbol: "paintbrush", detail: "Files and comments"),
        Connector(id: "dropbox", name: "Dropbox", category: "Files", symbol: "shippingbox", detail: "Shared folders"),
        Connector(id: "onedrive", name: "OneDrive", category: "Files", symbol: "cloud", detail: "Microsoft 365 files"),
        Connector(id: "confluence", name: "Confluence", category: "Knowledge", symbol: "book", detail: "Spaces and pages"),
        Connector(id: "salesforce", name: "Salesforce", category: "Sales", symbol: "chart.line.uptrend.xyaxis", detail: "Accounts and opportunities"),
        Connector(id: "hubspot", name: "HubSpot", category: "Sales", symbol: "person.2", detail: "Contacts and deals"),
        Connector(id: "discord", name: "Discord", category: "Community", symbol: "bubble.left.and.bubble.right", detail: "Server messages"),
        Connector(id: "telegram", name: "Telegram", category: "Community", symbol: "paperplane", detail: "Saved messages"),
        Connector(id: "chatgpt", name: "ChatGPT", category: "AI", symbol: "sparkle", detail: "Import chats and memory"),
        Connector(id: "claude", name: "Claude", category: "AI", symbol: "asterisk", detail: "Import projects and memory"),
        Connector(id: "gemini", name: "Gemini", category: "AI", symbol: "diamond", detail: "Import Gemini history"),
        Connector(id: "grok", name: "Grok", category: "AI", symbol: "x.circle", detail: "Import Grok conversations"),
        Connector(id: "perplexity", name: "Perplexity", category: "AI", symbol: "magnifyingglass", detail: "Import threads")
    ]

    static func connector(for id: String) -> Connector? {
        all.first(where: { $0.id == id })
    }

    static func categories() -> [String] {
        var seen: [String] = []
        for item in all where !seen.contains(item.category) { seen.append(item.category) }
        return seen
    }
}

struct QuickAction {
    let title: String
    let systemImage: String
    let prompt: String

    static let all: [QuickAction] = [
        QuickAction(title: "Write", systemImage: "pencil.line",
                    prompt: "Help me write "),
        QuickAction(title: "Learn", systemImage: "book",
                    prompt: "Explain this to me simply: "),
        QuickAction(title: "Code", systemImage: "chevron.left.forwardslash.chevron.right",
                    prompt: "Write code that "),
        QuickAction(title: "Life stuff", systemImage: "leaf",
                    prompt: "Help me plan "),
        QuickAction(title: "Notion AI's choice", systemImage: "sparkles",
                    prompt: "Surprise me with something useful from my workspace")
    ]
}

struct NotionPageSummary: Codable, Equatable {
    var id: String
    var title: String
    var icon: String?
    var url: String
    var snippet: String = ""

    var iconText: String { icon ?? "" }
}

struct NotionSpace: Codable, Equatable {
    var id: String
    var name: String
    var icon: String?
}
