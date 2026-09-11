import UIKit

enum SettingsGroup: Int, CaseIterable {
    case settings
    case customize

    var title: String {
        switch self {
        case .settings: return "SETTINGS"
        case .customize: return "CUSTOMIZE"
        }
    }
}

enum SettingsSection: String, CaseIterable {
    case general
    case account
    case privacy
    case billing
    case capabilities
    case memory
    case reflect
    case timeAndFocus
    case agents
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
        case .agents: return "Agents"
        case .skills: return "Skills"
        case .connectors: return "Connectors"
        case .plugins: return "Plugins"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .account: return "person.circle"
        case .privacy: return "lock"
        case .billing: return "creditcard"
        case .capabilities: return "wand.and.stars"
        case .memory: return "brain"
        case .reflect: return "chart.line.uptrend.xyaxis"
        case .timeAndFocus: return "clock"
        case .agents: return "person.2.badge.gearshape"
        case .skills: return "square.grid.2x2"
        case .connectors: return "link"
        case .plugins: return "puzzlepiece.extension"
        }
    }

    var group: SettingsGroup {
        switch self {
        case .agents, .skills, .connectors, .plugins: return .customize
        default: return .settings
        }
    }

    static func sections(in group: SettingsGroup) -> [SettingsSection] {
        allCases.filter { $0.group == group }
    }
}

struct SettingsRow {
    enum Accessory {
        case none
        case disclosure
        case checkmark(Bool)
        case toggle(Bool, (Bool) -> Void)
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
