import Foundation

final class AppSettings {
    static let shared = AppSettings()

    static let didChangeNotification = Notification.Name("AppSettingsDidChange")

    private let defaults = UserDefaults.standard

    private enum Key {
        static let chatFont = "settings.chatFont"
        static let reduceMotion = "settings.reduceMotion"
        static let haptics = "settings.haptics"
        static let hapticStrength = "settings.hapticStrength"
        static let modelID = "settings.modelID"
        static let effort = "settings.effort"
        static let mode = "settings.mode"
        static let sendOnReturn = "settings.sendOnReturn"
        static let aiEndpoint = "settings.aiEndpoint"
        static let memoryEnabled = "settings.memoryEnabled"
        static let analyticsOptOut = "settings.analyticsOptOut"
        static let quietHoursEnabled = "settings.quietHoursEnabled"
        static let quietHoursStart = "settings.quietHoursStart"
        static let quietHoursEnd = "settings.quietHoursEnd"
        static let connectors = "settings.connectors"
        static let defaultAgent = "settings.defaultAgent"
        static let activeSkills = "settings.activeSkills"
        static let diagnostics = "settings.diagnostics"
        static let lastRawResponse = "settings.lastRawResponse"
        static let lastRequestInfo = "settings.lastRequestInfo"
    }

    private init() {
        defaults.register(defaults: [
            Key.chatFont: ChatFontChoice.anthropicSerif.rawValue,
            Key.reduceMotion: false,
            Key.haptics: true,
            Key.hapticStrength: HapticStrength.full.rawValue,
            Key.modelID: AIModel.default.id,
            Key.effort: ModelEffort.balanced.rawValue,
            Key.mode: ChatMode.chat.rawValue,
            Key.sendOnReturn: true,
            Key.aiEndpoint: NotionEndpoints.defaultAIPath,
            Key.memoryEnabled: true,
            Key.analyticsOptOut: false,
            Key.quietHoursEnabled: false,
            Key.quietHoursStart: 22,
            Key.quietHoursEnd: 8,
            Key.diagnostics: true
        ])
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: AppSettings.didChangeNotification, object: nil)
    }

    var chatFont: ChatFontChoice {
        get { ChatFontChoice(rawValue: defaults.string(forKey: Key.chatFont) ?? "") ?? .anthropicSerif }
        set { defaults.set(newValue.rawValue, forKey: Key.chatFont); notifyChange() }
    }

    var reduceMotion: Bool {
        get { defaults.bool(forKey: Key.reduceMotion) }
        set { defaults.set(newValue, forKey: Key.reduceMotion); notifyChange() }
    }

    var motionReduced: Bool {
        reduceMotion || UIAccessibilityIsReduceMotionEnabledCompat()
    }

    var hapticsEnabled: Bool {
        get { hapticStrength != .off }
        set {
            hapticStrength = newValue ? .full : .off
        }
    }

    var hapticStrength: HapticStrength {
        get {
            if let raw = defaults.string(forKey: Key.hapticStrength),
               let value = HapticStrength(rawValue: raw) {
                return value
            }
            return defaults.bool(forKey: Key.haptics) ? .full : .off
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.hapticStrength)
            defaults.set(newValue != .off, forKey: Key.haptics)
            notifyChange()
        }
    }

    var selectedModel: AIModel {
        get { AIModel.model(for: defaults.string(forKey: Key.modelID) ?? AIModel.default.id) }
        set {
            defaults.set(newValue.id, forKey: Key.modelID)
            if !newValue.efforts.contains(effort) {
                defaults.set(newValue.defaultEffort.rawValue, forKey: Key.effort)
            }
            notifyChange()
        }
    }

    var effort: ModelEffort {
        get {
            let stored = ModelEffort(rawValue: defaults.string(forKey: Key.effort) ?? "") ?? .balanced
            let model = selectedModel
            return model.efforts.contains(stored) ? stored : model.defaultEffort
        }
        set { defaults.set(newValue.rawValue, forKey: Key.effort); notifyChange() }
    }

    var mode: ChatMode {
        get { ChatMode(rawValue: defaults.string(forKey: Key.mode) ?? "") ?? .chat }
        set { defaults.set(newValue.rawValue, forKey: Key.mode); notifyChange() }
    }

    var sendOnReturn: Bool {
        get { defaults.bool(forKey: Key.sendOnReturn) }
        set { defaults.set(newValue, forKey: Key.sendOnReturn); notifyChange() }
    }

    var aiEndpointPath: String {
        get {
            let value = defaults.string(forKey: Key.aiEndpoint) ?? NotionEndpoints.defaultAIPath
            return value.isEmpty ? NotionEndpoints.defaultAIPath : value
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.set(trimmed.isEmpty ? NotionEndpoints.defaultAIPath : trimmed, forKey: Key.aiEndpoint)
            notifyChange()
        }
    }

    var memoryEnabled: Bool {
        get { defaults.bool(forKey: Key.memoryEnabled) }
        set { defaults.set(newValue, forKey: Key.memoryEnabled); notifyChange() }
    }

    var analyticsOptOut: Bool {
        get { defaults.bool(forKey: Key.analyticsOptOut) }
        set { defaults.set(newValue, forKey: Key.analyticsOptOut); notifyChange() }
    }

    var diagnosticsEnabled: Bool {
        get { defaults.bool(forKey: Key.diagnostics) }
        set { defaults.set(newValue, forKey: Key.diagnostics); notifyChange() }
    }

    var quietHoursEnabled: Bool {
        get { defaults.bool(forKey: Key.quietHoursEnabled) }
        set { defaults.set(newValue, forKey: Key.quietHoursEnabled); notifyChange() }
    }

    var quietHoursStart: Int {
        get { defaults.integer(forKey: Key.quietHoursStart) }
        set { defaults.set(newValue, forKey: Key.quietHoursStart); notifyChange() }
    }

    var quietHoursEnd: Int {
        get { defaults.integer(forKey: Key.quietHoursEnd) }
        set { defaults.set(newValue, forKey: Key.quietHoursEnd); notifyChange() }
    }

    var isQuietTimeNow: Bool {
        guard quietHoursEnabled else { return false }
        let hour = Calendar.current.component(.hour, from: Date())
        let start = quietHoursStart
        let end = quietHoursEnd
        if start == end { return false }
        if start < end { return hour >= start && hour < end }
        return hour >= start || hour < end
    }

    // MARK: - Connectors

    var enabledConnectorIDs: [String] {
        get { defaults.stringArray(forKey: Key.connectors) ?? [] }
        set { defaults.set(newValue, forKey: Key.connectors); notifyChange() }
    }

    func isConnectorEnabled(_ id: String) -> Bool {
        enabledConnectorIDs.contains(id)
    }

    func setConnector(_ id: String, enabled: Bool) {
        var current = enabledConnectorIDs
        if enabled {
            guard !current.contains(id) else { return }
            current.append(id)
        } else {
            current.removeAll { $0 == id }
        }
        enabledConnectorIDs = current
    }

    // MARK: - Skills and agents

    var activeSkillIDs: [String] {
        get { defaults.stringArray(forKey: Key.activeSkills) ?? [] }
        set { defaults.set(newValue, forKey: Key.activeSkills); notifyChange() }
    }

    func isSkillActive(_ id: String) -> Bool {
        activeSkillIDs.contains(id)
    }

    func setSkill(_ id: String, active: Bool) {
        var current = activeSkillIDs
        if active {
            guard !current.contains(id) else { return }
            current.append(id)
        } else {
            current.removeAll { $0 == id }
        }
        activeSkillIDs = current
    }

    var defaultAgentID: String? {
        get { defaults.string(forKey: Key.defaultAgent) }
        set { defaults.set(newValue, forKey: Key.defaultAgent); notifyChange() }
    }

    // MARK: - Diagnostics

    var lastRawResponse: String {
        get { defaults.string(forKey: Key.lastRawResponse) ?? "" }
        set { defaults.set(String(newValue.prefix(20_000)), forKey: Key.lastRawResponse) }
    }

    var lastRequestInfo: String {
        get { defaults.string(forKey: Key.lastRequestInfo) ?? "" }
        set { defaults.set(String(newValue.prefix(4_000)), forKey: Key.lastRequestInfo) }
    }
}

import UIKit

private func UIAccessibilityIsReduceMotionEnabledCompat() -> Bool {
    UIAccessibility.isReduceMotionEnabled
}
