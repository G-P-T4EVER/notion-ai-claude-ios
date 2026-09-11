import Foundation

enum SettingsGroup: Int, CaseIterable {
    case settings
    case customize

    var title: String {
        switch self {
        case .settings: return "Settings"
        case .customize: return "Customize"
        }
    }
}

/// Mirrors the desktop client's settings sidebar one-to-one.
enum SettingsSection: String, CaseIterable {
    case general
    case account
    case privacy
    case billing
    case capabilities
    case memory
    case reflect
    case timeAndFocus
    case claudeCode
    case skills
    case connectors
    case plugins

    var title: String {
        switch self {
        case .general: return "General"
        case .account: return "Account"
        case .privacy: return "Privacy"
        case .billing: return "Billing"
        case .capabilities: return "Capabilities"
        case .memory: return "Memory"
        case .reflect: return "Reflect"
        case .timeAndFocus: return "Time and focus"
        case .claudeCode: return "Claude Code"
        case .skills: return "Skills"
        case .connectors: return "Connectors"
        case .plugins: return "Plugins"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .account: return "person.crop.circle"
        case .privacy: return "lock"
        case .billing: return "creditcard"
        case .capabilities: return "wand.and.stars"
        case .memory: return "brain"
        case .reflect: return "chart.bar"
        case .timeAndFocus: return "clock"
        case .claudeCode: return "terminal"
        case .skills: return "sparkles"
        case .connectors: return "puzzlepiece"
        case .plugins: return "square.stack.3d.up"
        }
    }

    var group: SettingsGroup {
        switch self {
        case .skills, .connectors, .plugins: return .customize
        default: return .settings
        }
    }

    static func sections(in group: SettingsGroup) -> [SettingsSection] {
        allCases.filter { $0.group == group }
    }
}

/// A single row inside a settings detail screen.
struct SettingsRow {
    enum Accessory {
        case none
        case checkmark(Bool)
        case toggle(Bool, (Bool) -> Void)
        case disclosure
        case value(String)
    }

    var title: String
    var subtitle: String?
    var accessory: Accessory = .none
    var destructive: Bool = false
    var action: (() -> Void)?
}

struct SettingsBlock {
    var header: String?
    var footer: String?
    var rows: [SettingsRow]
}
