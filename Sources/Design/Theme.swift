import UIKit

/// Palette lifted from the Claude desktop client (dark appearance).
enum Theme {
    static let background = UIColor(hex: 0x1A1A19)
    static let surface = UIColor(hex: 0x262624)
    static let surfaceRaised = UIColor(hex: 0x30302E)
    static let composer = UIColor(hex: 0x2A2A28)
    static let border = UIColor(hex: 0x3C3C39)
    static let borderStrong = UIColor(hex: 0x4A4A46)

    static let accent = UIColor(hex: 0xD97757)
    static let accentMuted = UIColor(hex: 0xD97757, alpha: 0.16)

    static let textPrimary = UIColor(hex: 0xF2F0EA)
    static let textSecondary = UIColor(hex: 0xA5A49E)
    static let textTertiary = UIColor(hex: 0x77766F)

    static let userBubble = UIColor(hex: 0x30302E)
    static let codeBackground = UIColor(hex: 0x1F1F1E)
    static let destructive = UIColor(hex: 0xE06C5A)

    /// Corner radius used by the composer and every pill-shaped control.
    static let composerRadius: CGFloat = 18
    static let cardRadius: CGFloat = 14
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: alpha
        )
    }
}

enum Haptics {
    static func tap() {
        guard AppSettings.shared.hapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func success() {
        guard AppSettings.shared.hapticsEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        guard AppSettings.shared.hapticsEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

extension UIView {
    func pinEdges(to other: UIView, insets: UIEdgeInsets = .zero) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: other.leadingAnchor, constant: insets.left),
            trailingAnchor.constraint(equalTo: other.trailingAnchor, constant: -insets.right),
            topAnchor.constraint(equalTo: other.topAnchor, constant: insets.top),
            bottomAnchor.constraint(equalTo: other.bottomAnchor, constant: -insets.bottom)
        ])
    }
}
