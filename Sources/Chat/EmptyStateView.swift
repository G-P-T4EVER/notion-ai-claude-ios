import UIKit

/// The "You're here!" greeting plus the five suggestion chips.
final class EmptyStateView: UIView {
    var onPick: ((QuickAction) -> Void)?

    private let mark = StarburstView()
    private let titleLabel = UILabel()
    private let chipsTop = UIStackView()
    private let chipsBottom = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        build()
    }

    private func build() {
        backgroundColor = .clear

        mark.color = Theme.accent
        mark.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mark)

        titleLabel.text = "You're here!"
        titleLabel.textColor = Theme.textPrimary
        titleLabel.font = AppSettings.shared.chatFont.font(size: 28)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        [chipsTop, chipsBottom].forEach { stack in
            stack.axis = .horizontal
            stack.spacing = 8
            stack.alignment = .center
            stack.distribution = .equalCentering
            stack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(stack)
        }

        let actions = QuickAction.all
        for (index, action) in actions.enumerated() {
            let chip = makeChip(action)
            (index < 3 ? chipsTop : chipsBottom).addArrangedSubview(chip)
        }

        NSLayoutConstraint.activate([
            mark.centerXAnchor.constraint(equalTo: centerXAnchor),
            mark.bottomAnchor.constraint(equalTo: titleLabel.topAnchor, constant: -14),
            mark.widthAnchor.constraint(equalToConstant: 22),
            mark.heightAnchor.constraint(equalToConstant: 22),

            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -40),

            chipsTop.centerXAnchor.constraint(equalTo: centerXAnchor),
            chipsTop.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 28),
            chipsTop.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),

            chipsBottom.centerXAnchor.constraint(equalTo: centerXAnchor),
            chipsBottom.topAnchor.constraint(equalTo: chipsTop.bottomAnchor, constant: 8),
            chipsBottom.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16)
        ])
    }

    private func makeChip(_ action: QuickAction) -> UIButton {
        let button = ChipButton(type: .system)
        button.quickAction = action
        button.setTitle(action.title, for: .normal)
        button.setImage(UIImage(systemName: action.systemImage), for: .normal)
        button.setTitleColor(Theme.textSecondary, for: .normal)
        button.tintColor = Theme.textSecondary
        button.titleLabel?.font = AppSettings.shared.chatFont.font(size: 14)
        button.backgroundColor = Theme.surface
        button.layer.cornerRadius = 17
        button.layer.borderWidth = 1
        button.layer.borderColor = Theme.border.cgColor
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 13, bottom: 8, right: 13)
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -4, bottom: 0, right: 4)
        button.addTarget(self, action: #selector(chipTapped(_:)), for: .touchUpInside)
        return button
    }

    @objc private func chipTapped(_ sender: ChipButton) {
        guard let action = sender.quickAction else { return }
        Haptics.tap()
        onPick?(action)
    }

    func refreshFonts() {
        titleLabel.font = AppSettings.shared.chatFont.font(size: 28)
        for stack in [chipsTop, chipsBottom] {
            for case let button as UIButton in stack.arrangedSubviews {
                button.titleLabel?.font = AppSettings.shared.chatFont.font(size: 14)
            }
        }
    }
}

/// UIButton subclass so a chip can carry its action without iOS 14 closures.
private final class ChipButton: UIButton {
    var quickAction: QuickAction?
}
