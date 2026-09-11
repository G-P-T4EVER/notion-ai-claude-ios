import Foundation

/// Local persistence for skills, agents and imported memory.
final class LibraryStore {
    static let shared = LibraryStore()

    static let didChangeNotification = Notification.Name("LibraryStoreDidChange")

    private struct Payload: Codable {
        var skills: [Skill]
        var agents: [AgentProfile]
        var memories: [MemoryItem]
    }

    private let queue = DispatchQueue(label: "com.sa1nt.notionclaude.library")
    private let fileURL: URL

    private(set) var skills: [Skill] = []
    private(set) var agents: [AgentProfile] = []
    private(set) var memories: [MemoryItem] = []

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("library.json")
        load()
    }

    // MARK: - Loading and saving

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            skills = LibraryStore.builtInSkills
            agents = LibraryStore.builtInAgents
            persist()
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let payload = try? decoder.decode(Payload.self, from: data) {
            skills = payload.skills
            agents = payload.agents
            memories = payload.memories
        } else {
            skills = LibraryStore.builtInSkills
            agents = LibraryStore.builtInAgents
        }
        if skills.isEmpty { skills = LibraryStore.builtInSkills }
    }

    private func persist() {
        let payload = Payload(skills: skills, agents: agents, memories: memories)
        queue.async { [fileURL] in
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            guard let data = try? encoder.encode(payload) else { return }
            try? data.write(to: fileURL, options: .atomic)
        }
        NotificationCenter.default.post(name: LibraryStore.didChangeNotification, object: nil)
    }

    // MARK: - Skills

    func skill(withID id: String) -> Skill? {
        skills.first(where: { $0.id == id })
    }

    func upsert(skill: Skill) {
        if let index = skills.firstIndex(where: { $0.id == skill.id }) {
            skills[index] = skill
        } else {
            skills.append(skill)
        }
        persist()
    }

    func deleteSkill(id: String) {
        skills.removeAll { $0.id == id && !$0.builtIn }
        AppSettings.shared.setSkill(id, active: false)
        persist()
    }

    func setSkillEnabled(id: String, enabled: Bool) {
        guard let index = skills.firstIndex(where: { $0.id == id }) else { return }
        skills[index].enabled = enabled
        persist()
    }

    var enabledSkills: [Skill] {
        skills.filter { $0.enabled }
    }

    var activeSkills: [Skill] {
        let active = AppSettings.shared.activeSkillIDs
        return skills.filter { active.contains($0.id) && $0.enabled }
    }

    // MARK: - Agents

    func agent(withID id: String) -> AgentProfile? {
        agents.first(where: { $0.id == id })
    }

    func upsert(agent: AgentProfile) {
        if let index = agents.firstIndex(where: { $0.id == agent.id }) {
            agents[index] = agent
        } else {
            agents.append(agent)
        }
        persist()
    }

    func deleteAgent(id: String) {
        agents.removeAll { $0.id == id }
        if AppSettings.shared.defaultAgentID == id {
            AppSettings.shared.defaultAgentID = nil
        }
        persist()
    }

    // MARK: - Memory

    func addMemories(_ items: [MemoryItem]) {
        memories.append(contentsOf: items)
        if memories.count > 2_000 {
            memories.removeFirst(memories.count - 2_000)
        }
        persist()
    }

    func addMemory(text: String, source: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        addMemories([MemoryItem(text: trimmed, source: source)])
    }

    func deleteMemory(id: String) {
        memories.removeAll { $0.id == id }
        persist()
    }

    func clearMemories(source: String? = nil) {
        if let source = source {
            memories.removeAll { $0.source == source }
        } else {
            memories.removeAll()
        }
        persist()
    }

    func memorySources() -> [(source: String, count: Int)] {
        var counts: [String: Int] = [:]
        for item in memories { counts[item.source, default: 0] += 1 }
        return counts.map { (source: $0.key, count: $0.value) }.sorted { $0.source < $1.source }
    }

    /// Short digest of memory injected into each request.
    func memoryDigest(limit: Int = 24) -> String {
        guard AppSettings.shared.memoryEnabled, !memories.isEmpty else { return "" }
        let recent = memories.suffix(limit)
        return recent.map { "- [\($0.source)] \($0.text)" }.joined(separator: "\n")
    }

    // MARK: - Import

    enum ImportError: LocalizedError {
        case unreadable
        case empty

        var errorDescription: String? {
            switch self {
            case .unreadable: return "This file is not a supported export."
            case .empty: return "No memory or messages were found in this file."
            }
        }
    }

    /// Parses exports from ChatGPT, Claude, Gemini, Grok and plain text/markdown.
    @discardableResult
    func importMemory(from data: Data, source: String) throws -> Int {
        var collected: [String] = []

        if let json = try? JSONSerialization.jsonObject(with: data) {
            collect(from: json, into: &collected)
        } else if let text = String(data: data, encoding: .utf8) {
            let lines = text
                .components(separatedBy: CharacterSet.newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.count > 3 }
            collected = lines
        } else {
            throw ImportError.unreadable
        }

        var seen = Set<String>()
        let items = collected
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 8 && $0.count <= 1_200 }
            .filter { seen.insert($0).inserted }
            .prefix(600)
            .map { MemoryItem(text: $0, source: source) }

        guard !items.isEmpty else { throw ImportError.empty }
        addMemories(Array(items))
        return items.count
    }

    private func collect(from json: Any, into result: inout [String], depth: Int = 0) {
        guard depth < 12, result.count < 4_000 else { return }

        if let dict = json as? [String: Any] {
            // ChatGPT memory export / custom instructions.
            for key in ["memory", "memories", "about_user_message", "about_model_message",
                        "user_profile", "instructions", "custom_instructions", "summary", "text",
                        "content", "value", "note", "fact"] {
                if let value = dict[key] {
                    if let string = value as? String {
                        result.append(string)
                    } else {
                        collect(from: value, into: &result, depth: depth + 1)
                    }
                }
            }
            // ChatGPT conversations.json: mapping -> message -> content -> parts
            if let parts = (dict["content"] as? [String: Any])?["parts"] as? [Any] {
                for part in parts {
                    if let string = part as? String { result.append(string) }
                }
            }
            for (key, value) in dict where !(value is String) {
                if ["mapping", "messages", "conversations", "chat_messages", "items", "data",
                    "chats", "turns", "history", "message", "projects"].contains(key) {
                    collect(from: value, into: &result, depth: depth + 1)
                }
            }
        } else if let array = json as? [Any] {
            for element in array.prefix(4_000) {
                if let string = element as? String {
                    result.append(string)
                } else {
                    collect(from: element, into: &result, depth: depth + 1)
                }
            }
        }
    }

    // MARK: - Seeds

    static let builtInSkills: [Skill] = [
        Skill(id: "skill-summarize", name: "Summarize page", icon: "✂️",
              prompt: "Summarise the page I mention in five bullet points, then list open questions.",
              enabled: true, builtIn: true),
        Skill(id: "skill-meeting", name: "Meeting notes", icon: "🗓️",
              prompt: "Turn my rough notes into structured meeting notes with decisions and action items.",
              enabled: true, builtIn: true),
        Skill(id: "skill-rewrite", name: "Rewrite sharper", icon: "✍️",
              prompt: "Rewrite the text to be shorter and clearer while keeping my voice.",
              enabled: true, builtIn: true),
        Skill(id: "skill-translate", name: "Translate", icon: "🌐",
              prompt: "Translate the following text, keeping formatting and tone. Ask for the target language if unclear.",
              enabled: true, builtIn: true),
        Skill(id: "skill-code-review", name: "Code review", icon: "🧪",
              prompt: "Review this code for bugs, edge cases and readability. Give concrete diffs.",
              enabled: true, builtIn: true),
        Skill(id: "skill-brainstorm", name: "Brainstorm", icon: "💡",
              prompt: "Give me ten distinct ideas, ranked, with a one-line reason for each.",
              enabled: true, builtIn: true)
    ]

    static let builtInAgents: [AgentProfile] = [
        AgentProfile(id: "agent-research", name: "Research buddy", icon: "🔍",
                     instructions: "You research topics across my workspace and the web. Always cite the page or link you used, and finish with a short 'what I would do next'.",
                     modelID: "opus-5", effortRaw: ModelEffort.high.rawValue, tone: "Analytical"),
        AgentProfile(id: "agent-editor", name: "Editor", icon: "🖋️",
                     instructions: "You are a ruthless editor. Cut filler, keep my voice, never add new claims. Return the edited text first, then a short list of what you changed.",
                     modelID: "fable-5-1", effortRaw: ModelEffort.balanced.rawValue, tone: "Direct")
    ]
}
