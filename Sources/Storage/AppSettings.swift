import Foundation
import UIKit

/// UserDefaults-backed mirror of the desktop client's settings surface.
final class AppSettings {
    static let shared = AppSettings()

    static let didChangeNotification = Notification.Name("AppSettingsDidChange")

    private let defaults = UserDefaults.standard

    private enum Key {
        static let chatFont = "settings.chatFont"
        static let reduceMotion = "settings.reduceMotion"
        static let haptics = "settings.haptics"
        static let modelID = "settings.modelID"
        static let mode = "settings.mode"
        static let sendOnReturn = "settings.sendOnReturn"
        static let aiEndpoint = "settings.aiEndpoint"
        static let memoryEnabled = "settings.memoryEnabled"
        static let analyticsOptOut = "settings.analyticsOptOut"
        static let quietHoursStart = "settings.quietHoursStart"
        static let quietHoursEnd = "settings.quietHoursEnd"
        static let quietHoursEnabled = "settings.quietHoursEnabled"
    }

    private init() {
        defaults.register(defaults: [
            Key.chatFont: ChatFontChoice.anthropicSerif.rawValue,
            Key.reduceMotion: false,
            Key.haptics: true,
            Key.modelID: AIModel.default.id,
            Key.mode: ChatMode.chat.rawValue,
            Key.sendOnReturn: false,
            Key.aiEndpoint: NotionEndpoints.defaultAIPath,
            Key.memoryEnabled: true,
            Key.analyticsOptOut: false,
            Key.quietHoursEnabled: false,
            Key.quietHoursStart: 22,
            Key.quietHoursEnd: 8
        ])
    }

    private func post() {
        NotificationCenter.default.post(name: AppSettings.didChangeNotification, object: nil)
    }

    var chatFont: ChatFontChoice {
        get { ChatFontChoice(rawValue: defaults.string(forKey: Key.chatFont) ?? "") ?? .anthropicSerif }
        set { defaults.set(newValue.rawValue, forKey: Key.chatFont); post() }
    }

    var reduceMotion: Bool {
        get { defaults.bool(forKey: Key.reduceMotion) }
        set { defaults.set(newValue, forKey: Key.reduceMotion); post() }
    }

    /// Honours both the in-app switch and the iOS accessibility setting.
    var motionReduced: Bool {
        reduceMotion || UIAccessibility.isReduceMotionEnabled
    }

    var hapticsEnabled: Bool {
        get { defaults.bool(forKey: Key.haptics) }
        set { defaults.set(newValue, forKey: Key.haptics) }
    }

    var selectedModel: AIModel {
        get { AIModel.model(for: defaults.string(forKey: Key.modelID) ?? AIModel.default.id) }
        set { defaults.set(newValue.id, forKey: Key.modelID); post() }
    }

    var mode: ChatMode {
        get { ChatMode(rawValue: defaults.string(forKey: Key.mode) ?? "") ?? .chat }
        set { defaults.set(newValue.rawValue, forKey: Key.mode); post() }
    }

    var sendOnReturn: Bool {
        get { defaults.bool(forKey: Key.sendOnReturn) }
        set { defaults.set(newValue, forKey: Key.sendOnReturn) }
    }

    /// Notion has no documented AI endpoint; keeping it editable means a server
    /// change can be fixed in-app instead of requiring a new build.
    var aiEndpointPath: String {
        get { defaults.string(forKey: Key.aiEndpoint) ?? NotionEndpoints.defaultAIPath }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.set(trimmed.isEmpty ? NotionEndpoints.defaultAIPath : trimmed, forKey: Key.aiEndpoint)
        }
    }

    var memoryEnabled: Bool {
        get { defaults.bool(forKey: Key.memoryEnabled) }
        set { defaults.set(newValue, forKey: Key.memoryEnabled) }
    }

    var analyticsOptOut: Bool {
        get { defaults.bool(forKey: Key.analyticsOptOut) }
        set { defaults.set(newValue, forKey: Key.analyticsOptOut) }
    }

    var quietHoursEnabled: Bool {
        get { defaults.bool(forKey: Key.quietHoursEnabled) }
        set { defaults.set(newValue, forKey: Key.quietHoursEnabled) }
    }

    var quietHoursStart: Int {
        get { defaults.integer(forKey: Key.quietHoursStart) }
        set { defaults.set(newValue, forKey: Key.quietHoursStart) }
    }

    var quietHoursEnd: Int {
        get { defaults.integer(forKey: Key.quietHoursEnd) }
        set { defaults.set(newValue, forKey: Key.quietHoursEnd) }
    }

    /// Drives the "Decide when Notion AI is off" row in Time and focus.
    var isQuietTimeNow: Bool {
        guard quietHoursEnabled else { return false }

        let hour = Calendar.current.component(.hour, from: Date())
        let start = max(0, min(23, quietHoursStart))
        let end = max(0, min(23, quietHoursEnd))

        if start == end { return false }
        if start < end { return hour >= start && hour < end }
        return hour >= start || hour < end
    }
}
