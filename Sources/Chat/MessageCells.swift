import UIKit

/// Right-aligned rounded bubble, exactly like the user turns in Claude.
final class UserMessageCell: UITableViewCell {
    static let reuseID = "UserMessageCell"

    private let bubble = UIView()
    private let label = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none

        bubble.backgroundColor = Theme.userBubble
        bubble.layer.cornerRadius = 18
        bubble.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bubble)

        label.numberOfLines = 0
        label.textColor = Theme.textPrimary
        label.translatesAutoresizingMaskIntoConstraints = false
        bubble.addSubview(label)

        NSLayoutConstraint.activate([
            bubble.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            bubble.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            bubble.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            bubble.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 64),
            label.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 11),
            label.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -11),
            label.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -14)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with message: ChatMessage) {
        let font = AppSettings.shared.chatFont
        label.attributedText = NSAttributedString(
            string: message.text,
            attributes: font.attributes()
        )
    }
}

/// Assistant turn: starburst in the gutter, optional activity rows, Markdown
/// body and a blinking caret while streaming.
final class AssistantMessageCell: UITableViewCell {
    static let reuseID = "AssistantMessageCell"

    private let mark = StarburstView()
    private let activityStack = UIStackView()
    private let bodyLabel = UILabel()
    private let caret = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none

        mark.color = Theme.accent
        mark.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(mark)

        activityStack.axis = .vertical
        activityStack.spacing = 4
        activityStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(activityStack)

        bodyLabel.numberOfLines = 0
        bodyLabel.textColor = Theme.textPrimary
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bodyLabel)

        caret.backgroundColor = Theme.accent
        caret.layer.cornerRadius = 1
        caret.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(caret)

        NSLayoutConstraint.activate([
            mark.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            mark.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            mark.widthAnchor.constraint(equalToConstant: 18),
            mark.heightAnchor.constraint(equalToConstant: 18),

            activityStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            activityStack.leadingAnchor.constraint(equalTo: mark.trailingAnchor, constant: 12),
            activityStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            bodyLabel.topAnchor.constraint(equalTo: activityStack.bottomAnchor, constant: 4),
            bodyLabel.leadingAnchor.constraint(equalTo: activityStack.leadingAnchor),
            bodyLabel.trailingAnchor.constraint(equalTo: activityStack.trailingAnchor),
            bodyLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),

            caret.leadingAnchor.constraint(equalTo: bodyLabel.leadingAnchor),
            caret.bottomAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: -2),
            caret.widthAnchor.constraint(equalToConstant: 2),
            caret.heightAnchor.constraint(equalToConstant: 16)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with message: ChatMessage) {
        let font = AppSettings.shared.chatFont

        activityStack.arrangedSubviews.forEach { view in
            activityStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        message.activity.forEach { note in
            activityStack.addArrangedSubview(AssistantMessageCell.activityRow(note, font: font))
        }

        if message.failed {
            bodyLabel.attributedText = NSAttributedString(
                string: message.text.isEmpty ? "Something went wrong." : message.text,
                attributes: [
                    .font: font.font(size: 16),
                    .foregroundColor: Theme.destructive
                ]
            )
        } else {
            bodyLabel.attributedText = Markdown.render(message.text, font: font)
        }

        let streaming = message.isStreaming && !message.failed
        caret.isHidden = !streaming
        streaming ? startCaret() : stopCaret()
        streaming && message.text.isEmpty ? mark.startSpinning() : mark.stopSpinning()
    }

    private static func activityRow(_ note: ActivityNote, font: ChatFontChoice) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 6
        row.alignment = .center

        let icon = UIImageView(image: UIImage(systemName: note.symbol))
        icon.tintColor = Theme.textTertiary
        icon.contentMode = .scaleAspectFit
        icon.widthAnchor.constraint(equalToConstant: 13).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 13).isActive = true

        let label = UILabel()
        label.text = note.text
        label.textColor = Theme.textTertiary
        label.font = font.font(size: 13)

        row.addArrangedSubview(icon)
        row.addArrangedSubview(label)
        return row
    }

    private func startCaret() {
        guard !AppSettings.shared.motionReduced else {
            caret.alpha = 1
            return
        }
        guard caret.layer.animation(forKey: "blink") == nil else { return }

        let blink = CABasicAnimation(keyPath: "opacity")
        blink.fromValue = 1
        blink.toValue = 0.1
        blink.duration = 0.55
        blink.autoreverses = true
        blink.repeatCount = .infinity
        caret.layer.add(blink, forKey: "blink")
    }

    private func stopCaret() {
        caret.layer.removeAnimation(forKey: "blink")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        stopCaret()
        mark.stopSpinning()
    }
}
