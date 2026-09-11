import UIKit

final class EmptyStateView: UIView {
    var onPick: ((QuickAction) -> Void)?

    private let mark = BrandMarkView(rays: 11)
    private let greetingLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let chipsStack = UIStackView()
    private let contentStack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        backgroundColor = .clear

        mark.translatesAutoresizingMaskIntoConstraints = false
        mark.heightAnchor.constraint(equalToConstant: 46).isActive = true
        mark.widthAnchor.constraint(equalToConstant: 46).isActive = true

        let markHolder = UIView()
        markHolder.translatesAutoresizingMaskIntoConstraints = false
        markHolder.addSubview(mark)
        NSLayoutConstraint.activate([
            mark.centerXAnchor.constraint(equalTo: markHolder.centerXAnchor),
            mark.topAnchor.constraint(equalTo: markHolder.topAnchor),
            mark.bottomAnchor.constraint(equalTo: markHolder.bottomAnchor)
        ])

        greetingLabel.translatesAutoresizingMaskIntoConstraints = false
        greetingLabel.textAlignment = .center
        greetingLabel.numberOfLines = 0
        greetingLabel.textColor = Theme.textPrimary

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        subtitleLabel.textColor = Theme.textTertiary

        chipsStack.translatesAutoresizingMaskIntoConstraints = false
        chipsStack.axis = .vertical
        chipsStack.spacing = 10
        chipsStack.alignment = .center

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 14
        contentStack.addArrangedSubview(markHolder)
        contentStack.addArrangedSubview(greetingLabel)
        contentStack.addArrangedSubview(subtitleLabel)
        contentStack.addArrangedSubview(chipsStack)
        contentStack.setCustomSpacing(18, after: markHolder)
        contentStack.setCustomSpacing(6, after: greetingLabel)
        contentStack.setCustomSpacing(22, after: subtitleLabel)

        addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -12),
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 26),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -26),
            contentStack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 16),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -16)
        ])

        buildChips()
        refreshGreeting()
        refreshFonts()
    }

    private func buildChips() {
        chipsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        var row = makeRow()
        var rowWidth: CGFloat = 0
        let maxWidth = UIScreen.main.bounds.width - 60

        for action in QuickAction.all {
            let chip = ChipButton(action: action)
            chip.addTarget(self, action: #selector(chipTapped(_:)), for: .touchUpInside)
            chip.addHapticFeedback(.tap)
            let width = chip.intrinsicContentSize.width
            if rowWidth + width > maxWidth, !row.arrangedSubviews.isEmpty {
                chipsStack.addArrangedSubview(row)
                row = makeRow()
                rowWidth = 0
            }
            row.addArrangedSubview(chip)
            rowWidth += width + 8
        }
        if !row.arrangedSubviews.isEmpty {
            chipsStack.addArrangedSubview(row)
        }
    }

    private func makeRow() -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .center
        return row
    }

    @objc private func chipTapped(_ sender: ChipButton) {
        Feedback.tap()
        guard let action = sender.quickAction else { return }
        onPick?(action)
    }

    func refreshGreeting() {
        let name = NotionSession.shared.userName
        greetingLabel.text = Greeting.random(name: name)

        let model = AppSettings.shared.selectedModel
        if model.id == AIModel.auto.id {
            subtitleLabel.text = "Auto picks the right model for each message"
        } else {
            subtitleLabel.text = "\(model.name) · \(AppSettings.shared.effort.title)"
        }

        mark.setNeedsDisplay()
        mark.pulse()

        guard !AppSettings.shared.motionReduced else { return }
        greetingLabel.alpha = 0
        UIView.animate(withDuration: 0.35) { self.greetingLabel.alpha = 1 }
    }

    func refreshFonts() {
        let font = AppSettings.shared.chatFont
        greetingLabel.font = font.font(size: 27, weight: .semibold)
        subtitleLabel.font = font.font(size: 13, weight: .regular)
        chipsStack.arrangedSubviews
            .compactMap { $0 as? UIStackView }
            .flatMap { $0.arrangedSubviews }
            .compactMap { $0 as? ChipButton }
            .forEach { $0.refreshFont() }
        refreshGreeting()
    }
}

final class ChipButton: UIButton {
    var quickAction: QuickAction?

    init(action: QuickAction) {
        self.quickAction = action
        super.init(frame: .zero)

        setTitle(action.title, for: .normal)
        setTitleColor(Theme.textSecondary, for: .normal)
        setImage(UIImage(systemName: action.systemImage), for: .normal)
        tintColor = Theme.textTertiary
        backgroundColor = Theme.surface
        layer.cornerRadius = 17
        layer.borderWidth = 1
        layer.borderColor = Theme.border.cgColor
        contentEdgeInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 16)
        imageEdgeInsets = UIEdgeInsets(top: 0, left: -4, bottom: 0, right: 4)
        titleEdgeInsets = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 0)
        refreshFont()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func refreshFont() {
        titleLabel?.font = AppSettings.shared.chatFont.font(size: 14, weight: .medium)
    }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            let scale: CGFloat = isHighlighted ? 0.96 : 1
            UIView.animate(withDuration: 0.12) {
                self.transform = CGAffineTransform(scaleX: scale, y: scale)
                self.backgroundColor = self.isHighlighted ? Theme.surfaceRaised : Theme.surface
            }
        }
    }
}
