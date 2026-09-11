import UIKit

protocol ComposerViewDelegate: AnyObject {
    func composerDidSend(_ text: String)
    func composerDidTapStop()
    func composerDidTapPlus()
    func composerDidTapModel()
    func composerDidTapSkills()
    func composerDidChangeMode(_ mode: ChatMode)
    func composerHeightChanged()
    func composerNeedsPresenter() -> UIViewController
}

final class ComposerView: UIView {
    weak var delegate: ComposerViewDelegate?

    private let card = UIView()
    private let textView = UITextView()
    private let placeholder = UILabel()

    private let plusButton = UIButton(type: .system)
    private let skillsButton = UIButton(type: .system)
    private let modeButton = UIButton(type: .system)
    private let modelButton = UIButton(type: .system)
    private let micButton = UIButton(type: .system)
    private let sendButton = UIButton(type: .system)
    private let levelView = UIProgressView(progressViewStyle: .bar)

    private let dictation = Dictation()
    private var isDictating = false
    private var heightConstraint: NSLayoutConstraint!

    private(set) var isStreaming = false

    var text: String {
        get { textView.text ?? "" }
        set {
            textView.text = newValue
            updatePlaceholder()
            recalculateHeight()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsChanged),
            name: AppSettings.didChangeNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Build

    private func build() {
        backgroundColor = .clear

        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = Theme.composer
        card.layer.cornerRadius = 24
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1
        card.layer.borderColor = Theme.border.cgColor
        addSubview(card)

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = .clear
        textView.textColor = Theme.textPrimary
        textView.tintColor = Theme.accent
        textView.delegate = self
        textView.isScrollEnabled = false
        textView.keyboardAppearance = .dark
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.returnKeyType = AppSettings.shared.sendOnReturn ? .send : .default
        card.addSubview(textView)

        placeholder.translatesAutoresizingMaskIntoConstraints = false
        placeholder.text = "Type / for skills"
        placeholder.textColor = Theme.textTertiary
        card.addSubview(placeholder)

        configureIcon(plusButton, systemName: "plus", action: #selector(plusTapped))
        configureIcon(skillsButton, systemName: "square.grid.2x2", action: #selector(skillsTapped))
        configureIcon(micButton, systemName: "mic", action: #selector(micTapped))

        modeButton.translatesAutoresizingMaskIntoConstraints = false
        modeButton.backgroundColor = Theme.surfaceRaised
        modeButton.layer.cornerRadius = 15
        modeButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        modeButton.setTitleColor(Theme.textSecondary, for: .normal)
        modeButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        modeButton.addTarget(self, action: #selector(modeTapped), for: .touchUpInside)
        card.addSubview(modeButton)

        modelButton.translatesAutoresizingMaskIntoConstraints = false
        modelButton.backgroundColor = .clear
        modelButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 4, bottom: 6, right: 8)
        modelButton.setTitleColor(Theme.textSecondary, for: .normal)
        modelButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        modelButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 6)
        modelButton.titleEdgeInsets = UIEdgeInsets(top: 0, left: 6, bottom: 0, right: 0)
        modelButton.addTarget(self, action: #selector(modelTapped), for: .touchUpInside)
        card.addSubview(modelButton)

        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.backgroundColor = Theme.accent
        sendButton.tintColor = UIColor(hex: 0x1A1A19)
        sendButton.layer.cornerRadius = 17
        sendButton.setImage(UIImage(systemName: "arrow.up"), for: .normal)
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        card.addSubview(sendButton)

        levelView.translatesAutoresizingMaskIntoConstraints = false
        levelView.progressTintColor = Theme.accent
        levelView.trackTintColor = Theme.border
        levelView.isHidden = true
        card.addSubview(levelView)

        heightConstraint = textView.heightAnchor.constraint(equalToConstant: 22)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: topAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),
            card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            textView.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            textView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            textView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            heightConstraint,

            placeholder.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            placeholder.topAnchor.constraint(equalTo: textView.topAnchor),

            levelView.topAnchor.constraint(equalTo: textView.bottomAnchor, constant: 8),
            levelView.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            levelView.trailingAnchor.constraint(equalTo: textView.trailingAnchor),
            levelView.heightAnchor.constraint(equalToConstant: 2),

            plusButton.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            plusButton.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10),
            plusButton.widthAnchor.constraint(equalToConstant: 34),
            plusButton.heightAnchor.constraint(equalToConstant: 34),

            skillsButton.leadingAnchor.constraint(equalTo: plusButton.trailingAnchor, constant: 2),
            skillsButton.centerYAnchor.constraint(equalTo: plusButton.centerYAnchor),
            skillsButton.widthAnchor.constraint(equalToConstant: 34),
            skillsButton.heightAnchor.constraint(equalToConstant: 34),

            modeButton.leadingAnchor.constraint(equalTo: skillsButton.trailingAnchor, constant: 4),
            modeButton.centerYAnchor.constraint(equalTo: plusButton.centerYAnchor),

            modelButton.leadingAnchor.constraint(equalTo: modeButton.trailingAnchor, constant: 2),
            modelButton.centerYAnchor.constraint(equalTo: plusButton.centerYAnchor),
            modelButton.trailingAnchor.constraint(lessThanOrEqualTo: micButton.leadingAnchor, constant: -4),

            micButton.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -2),
            micButton.centerYAnchor.constraint(equalTo: plusButton.centerYAnchor),
            micButton.widthAnchor.constraint(equalToConstant: 34),
            micButton.heightAnchor.constraint(equalToConstant: 34),

            sendButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            sendButton.centerYAnchor.constraint(equalTo: plusButton.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 34),
            sendButton.heightAnchor.constraint(equalToConstant: 34),

            plusButton.topAnchor.constraint(greaterThanOrEqualTo: levelView.bottomAnchor, constant: 6)
        ])

        modelButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        refreshLabels()
        updatePlaceholder()
    }

    private func configureIcon(_ button: UIButton, systemName: String, action: Selector) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = Theme.textSecondary
        button.setImage(UIImage(systemName: systemName), for: .normal)
        button.addTarget(self, action: action, for: .touchUpInside)
        card.addSubview(button)
    }

    // MARK: - State

    func refreshLabels() {
        let settings = AppSettings.shared
        let model = settings.selectedModel

        modeButton.setTitle(settings.mode.title, for: .normal)

        let effortSuffix = model.supportsEffort ? "  " + settings.effort.title : ""
        modelButton.setTitle(model.name + effortSuffix, for: .normal)
        modelButton.setImage(ProviderMark.image(for: model.provider, size: 16), for: .normal)

        textView.font = settings.chatFont.bodyFont()
        placeholder.font = settings.chatFont.bodyFont()
        textView.returnKeyType = settings.sendOnReturn ? .send : .default
        recalculateHeight()
    }

    @objc private func settingsChanged() {
        refreshLabels()
    }

    func setStreaming(_ streaming: Bool) {
        isStreaming = streaming
        let image = streaming ? "stop.fill" : "arrow.up"
        sendButton.setImage(UIImage(systemName: image), for: .normal)
        sendButton.backgroundColor = streaming ? Theme.surfaceRaised : Theme.accent
        sendButton.tintColor = streaming ? Theme.textPrimary : UIColor(hex: 0x1A1A19)
    }

    private func updatePlaceholder() {
        placeholder.isHidden = !(textView.text ?? "").isEmpty
    }

    private func recalculateHeight() {
        let width = max(textView.bounds.width, 1)
        let size = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let clamped = min(max(size.height, 22), 150)
        guard abs(clamped - heightConstraint.constant) > 0.5 else { return }
        heightConstraint.constant = clamped
        textView.isScrollEnabled = clamped >= 150
        delegate?.composerHeightChanged()
    }

    // MARK: - Actions

    @objc private func plusTapped() {
        Feedback.tap()
        delegate?.composerDidTapPlus()
    }

    @objc private func skillsTapped() {
        Feedback.tap()
        delegate?.composerDidTapSkills()
    }

    @objc private func modelTapped() {
        Feedback.tap()
        delegate?.composerDidTapModel()
    }

    @objc private func modeTapped() {
        Feedback.selection()
        let next: ChatMode = AppSettings.shared.mode == .chat ? .cowork : .chat
        AppSettings.shared.mode = next
        refreshLabels()
        delegate?.composerDidChangeMode(next)
    }

    @objc private func sendTapped() {
        if isStreaming {
            Feedback.warning()
            delegate?.composerDidTapStop()
            return
        }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            Feedback.tick()
            return
        }
        Feedback.send()
        stopDictation()
        text = ""
        delegate?.composerDidSend(value)
    }

    @objc private func micTapped() {
        if isDictating {
            Feedback.tap()
            stopDictation()
            return
        }

        Feedback.tap()
        isDictating = true
        micButton.tintColor = Theme.accent
        micButton.setImage(UIImage(systemName: "mic.fill"), for: .normal)
        levelView.isHidden = false

        dictation.start(
            onTranscript: { [weak self] transcript in
                guard let self = self else { return }
                self.text = transcript
            },
            onLevel: { [weak self] level in
                self?.levelView.setProgress(min(max(level, 0), 1), animated: false)
            },
            onError: { [weak self] error in
                guard let self = self else { return }
                self.stopDictation()
                Feedback.error()
                let alert = UIAlertController(
                    title: "Dictation unavailable",
                    message: error.localizedDescription,
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self.delegate?.composerNeedsPresenter().present(alert, animated: true)
            }
        )
    }

    func stopDictation() {
        guard isDictating else { return }
        isDictating = false
        dictation.stop()
        micButton.tintColor = Theme.textSecondary
        micButton.setImage(UIImage(systemName: "mic"), for: .normal)
        levelView.isHidden = true
        levelView.setProgress(0, animated: false)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        recalculateHeight()
    }
}

extension ComposerView: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        updatePlaceholder()
        recalculateHeight()
        Feedback.tick()

        if textView.text == "/" {
            textView.text = ""
            updatePlaceholder()
            delegate?.composerDidTapSkills()
        }
    }

    func textView(
        _ textView: UITextView,
        shouldChangeTextIn range: NSRange,
        replacementText text: String
    ) -> Bool {
        guard text == "\n", AppSettings.shared.sendOnReturn else { return true }
        sendTapped()
        return false
    }
}
