import UIKit

final class UserMessageCell: UITableViewCell {
    static let reuseID = "UserMessageCell"

    private let bubble = UIView()
    private let label = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none

        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.backgroundColor = Theme.userBubble
        bubble.layer.cornerRadius = 18
        bubble.layer.cornerCurve = .continuous
        contentView.addSubview(bubble)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.textColor = Theme.textPrimary
        bubble.addSubview(label)

        NSLayoutConstraint.activate([
            bubble.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            bubble.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            bubble.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            bubble.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 62),

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

final class AssistantMessageCell: UITableViewCell {
    static let reuseID = "AssistantMessageCell"

    private let mark = BrandMarkView(rays: 11)
    private let stack = UIStackView()
    private let modelLabel = UILabel()
    private let bodyLabel = UILabel()
    private let progressLabel = UILabel()
    private let activityLabel = UILabel()
    private let errorLabel = UILabel()
    private var shimmerTimer: Timer?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none

        mark.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(mark)

        modelLabel.numberOfLines = 1
        modelLabel.textColor = Theme.textTertiary
        modelLabel.font = .systemFont(ofSize: 11, weight: .semibold)

        bodyLabel.numberOfLines = 0
        bodyLabel.textColor = Theme.textPrimary

        progressLabel.numberOfLines = 0
        progressLabel.textColor = Theme.textSecondary.withAlphaComponent(0.55)
        progressLabel.font = .systemFont(ofSize: 14, weight: .regular)

        activityLabel.numberOfLines = 0
        activityLabel.textColor = Theme.textTertiary
        activityLabel.font = .systemFont(ofSize: 12)

        errorLabel.numberOfLines = 0
        errorLabel.textColor = Theme.destructive
        errorLabel.font = .systemFont(ofSize: 13)

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 6
        stack.alignment = .fill
        stack.addArrangedSubview(modelLabel)
        stack.addArrangedSubview(progressLabel)
        stack.addArrangedSubview(bodyLabel)
        stack.addArrangedSubview(activityLabel)
        stack.addArrangedSubview(errorLabel)
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            mark.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            mark.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            mark.widthAnchor.constraint(equalToConstant: 18),
            mark.heightAnchor.constraint(equalToConstant: 18),

            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: mark.trailingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        stopShimmer()
    }

    func configure(with message: ChatMessage) {
        let font = AppSettings.shared.chatFont

        if let modelID = message.modelID {
            let model = AIModel.model(for: modelID)
            modelLabel.text = model.name.uppercased()
            modelLabel.isHidden = false
        } else {
            modelLabel.isHidden = true
        }

        let trimmed = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            bodyLabel.isHidden = true
            bodyLabel.attributedText = nil
        } else {
            bodyLabel.isHidden = false
            bodyLabel.attributedText = Markdown.render(message.text, font: font)
        }

        if message.isStreaming, let progress = message.progress, !progress.isEmpty, trimmed.isEmpty {
            progressLabel.isHidden = false
            progressLabel.text = progress
            startShimmer()
        } else {
            progressLabel.isHidden = true
            stopShimmer()
        }

        let notes = message.activity
        if notes.isEmpty {
            activityLabel.isHidden = true
        } else {
            activityLabel.isHidden = false
            activityLabel.text = notes.map { "· " + $0.text }.joined(separator: "\n")
        }

        if message.failed {
            errorLabel.isHidden = false
            errorLabel.text = trimmed.isEmpty
                ? "This request failed. Pull the message up to retry, or check Settings → Capabilities."
                : nil
            errorLabel.isHidden = errorLabel.text == nil
        } else {
            errorLabel.isHidden = true
        }

        mark.alpha = message.isStreaming ? 0.9 : 0.55
    }

    private func startShimmer() {
        guard shimmerTimer == nil else { return }
        guard !AppSettings.shared.motionReduced else {
            progressLabel.alpha = 1
            return
        }
        var goingDown = true
        let timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            UIView.animate(withDuration: 0.75) {
                self.progressLabel.alpha = goingDown ? 0.45 : 1.0
            }
            goingDown.toggle()
        }
        RunLoop.main.add(timer, forMode: .common)
        shimmerTimer = timer
    }

    private func stopShimmer() {
        shimmerTimer?.invalidate()
        shimmerTimer = nil
        progressLabel.alpha = 1
    }
}
