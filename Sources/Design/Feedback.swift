import UIKit

enum HapticStrength: String, CaseIterable {
    case off
    case subtle
    case standard
    case full

    var title: String {
        switch self {
        case .off: return "Off"
        case .subtle: return "Subtle"
        case .standard: return "Standard"
        case .full: return "Full"
        }
    }

    var detail: String {
        switch self {
        case .off: return "No vibration"
        case .subtle: return "Only key actions"
        case .standard: return "Balanced, like Claude"
        case .full: return "Every tap responds"
        }
    }

    var scale: CGFloat {
        switch self {
        case .off: return 0
        case .subtle: return 0.45
        case .standard: return 0.75
        case .full: return 1.0
        }
    }
}

/// Centralised haptics so the whole UI feels consistent and "expensive".
enum Feedback {
    private static var light = UIImpactFeedbackGenerator(style: .light)
    private static var medium = UIImpactFeedbackGenerator(style: .medium)
    private static var soft = UIImpactFeedbackGenerator(style: .soft)
    private static var rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static var selectionGenerator = UISelectionFeedbackGenerator()
    private static var notification = UINotificationFeedbackGenerator()

    private static var strength: HapticStrength { AppSettings.shared.hapticStrength }

    static func prepare() {
        guard strength != .off else { return }
        light.prepare()
        soft.prepare()
        selectionGenerator.prepare()
    }

    /// The lightest possible tick: list scrolling, chip highlight, keyboard-ish taps.
    static func tick() {
        guard strength == .full else { return }
        soft.impactOccurred(intensity: 0.35 * strength.scale)
        soft.prepare()
    }

    /// Standard button tap.
    static func tap() {
        guard strength != .off else { return }
        light.impactOccurred(intensity: 0.55 * strength.scale)
        light.prepare()
    }

    /// Picking an item in a list or segmented control.
    static func selection() {
        guard strength != .off else { return }
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }

    /// A switch or toggle flipping.
    static func toggle(_ on: Bool) {
        guard strength != .off else { return }
        if on {
            rigid.impactOccurred(intensity: 0.6 * strength.scale)
        } else {
            soft.impactOccurred(intensity: 0.5 * strength.scale)
        }
    }

    /// Sending a message: a double beat that feels like a "whoosh".
    static func send() {
        guard strength != .off else { return }
        medium.impactOccurred(intensity: 0.7 * strength.scale)
        medium.prepare()
        guard strength == .full else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) {
            soft.impactOccurred(intensity: 0.35)
        }
    }

    /// First token of a streamed answer.
    static func streamStart() {
        guard strength == .full else { return }
        soft.impactOccurred(intensity: 0.3)
    }

    /// Sheet or drawer opening / closing.
    static func sheet() {
        guard strength != .off else { return }
        soft.impactOccurred(intensity: 0.5 * strength.scale)
        soft.prepare()
    }

    static func success() {
        guard strength != .off else { return }
        notification.notificationOccurred(.success)
    }

    static func warning() {
        guard strength != .off else { return }
        notification.notificationOccurred(.warning)
    }

    static func error() {
        guard strength != .off else { return }
        notification.notificationOccurred(.error)
    }
}

extension UIControl {
    /// Adds a haptic tick on touch-down for every control that uses it.
    func addHapticFeedback(_ kind: HapticKind = .tap) {
        switch kind {
        case .tap:
            addTarget(HapticProxy.shared, action: #selector(HapticProxy.tap), for: .touchDown)
        case .selection:
            addTarget(HapticProxy.shared, action: #selector(HapticProxy.selection), for: .touchDown)
        }
    }

    enum HapticKind {
        case tap
        case selection
    }
}

final class HapticProxy: NSObject {
    static let shared = HapticProxy()

    @objc func tap() { Feedback.tap() }
    @objc func selection() { Feedback.selection() }
}
