import UIKit

/// Mirrors the desktop client's Settings -> Chat font picker.
enum ChatFontChoice: String, CaseIterable, Codable {
    case anthropicSerif
    case anthropicSans
    case system
    case dyslexicFriendly

    var title: String {
        switch self {
        case .anthropicSerif: return "Anthropic Serif"
        case .anthropicSans: return "Anthropic Sans"
        case .system: return "System"
        case .dyslexicFriendly: return "Dyslexic friendly"
        }
    }

    /// Anthropic ships proprietary faces (Styrene / Tiempos) that cannot be
    /// redistributed here, so each option maps onto the closest system design.
    private var design: UIFontDescriptor.SystemDesign {
        switch self {
        case .anthropicSerif: return .serif
        case .anthropicSans: return .default
        case .system: return .default
        case .dyslexicFriendly: return .monospaced
        }
    }

    var extraTracking: CGFloat {
        self == .dyslexicFriendly ? 0.6 : 0
    }

    var lineHeightMultiple: CGFloat {
        switch self {
        case .anthropicSerif: return 1.28
        case .dyslexicFriendly: return 1.42
        default: return 1.22
        }
    }

    func font(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(design) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    /// Body copy for assistant/user messages, scaled for Dynamic Type.
    func bodyFont() -> UIFont {
        let size = min(UIFont.preferredFont(forTextStyle: .body).pointSize, 22)
        return font(size: size)
    }

    func paragraphStyle() -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = lineHeightMultiple
        style.paragraphSpacing = 10
        return style
    }

    func attributes(color: UIColor = Theme.textPrimary) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: bodyFont(),
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle()
        ]
        if extraTracking > 0 {
            attributes[.kern] = extraTracking
        }
        return attributes
    }
}
