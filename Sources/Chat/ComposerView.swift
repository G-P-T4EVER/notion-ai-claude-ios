import UIKit

protocol ComposerViewDelegate: AnyObject {
    func composerDidSend(_ text: String)
    func composerDidTapStop()
    func composerDidTapPlus()
    func composerDidTapModel()
    func composerDidChangeMode(_ mode: ChatMode)
    func composerDidTapVoiceMode()
    func composerHeightChanged()
    func composerNeedsPresenter() -> UIViewController
}

/// The Claude composer: rounded card, growing text view, `+` button, the
/// Chat/Cowork pill, the model pill, dictation mic and the waveform button.
final class ComposerView: UIView {
    weak var delegate: ComposerViewDelegate?

    private let card = UIView()
    private let textView = UITextView()
    private let placeholder = UILabel()
    private let plusButton = UIButton(type: .system)
    private let modeButton = UIButton(type: .system)
    private let modelButton = UIButton(type: .system)
    private let micButton = UIButton(type: .system)
    private let waveButton = UIButton(type: .system)
    private let sendButton = UIButton(type: .system)

    private let dictation = Dictation()
    private var textHeight: NSLayoutConstraint!
    private let minHeight: CGFloat = 24
    private let maxHeight: CGFloat = 160

    private(set) var isStreaming = false

    var text: String {
        get { textView.text ?? "" }
        set {
            textView.text = newValue
            refreshState()
            recalculateHeight()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        build()
    }

    // MARK: - Construction

    private func build() {
        backgroundColor = .clear

        card.backgroundColor = Theme.composer
        card.layer.cornerRadius = 24
        card.layer.borderWidth = 1
        card.layer.borderColor = Theme.border.cgColor
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

        textView.backgroundColor = .clear
        textView.textColor = Theme.textPrimary
        textView.font = AppSettings.shared.chatFont.bodyFont()
        textView.delegate = self
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.keyboardAppearance = .dark
        textView.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(textView)

        placeholder.text = "Type / for skills"
        placeholder.textColor = Theme.textTertiary
        placeholder.font = AppSettings.shared.chatFont.bodyFont()
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(placeholder)

        configureIconButton(plusButton, symbol: "plus", action: #selector(plusTapped))
        configureIconButton(micButton, symbol: "mic", action: #selector(micTapped))
        configureIconButton(waveButton, symbol: "waveform", action: #selector(waveTapped))

        sendButton.setImage(UIImage(systemName: "arrow.up"), for: .normal)
        sendButton.tintColor = Theme.background
        sendButton.backgroundColor = Theme.accent
        sendButton.layer.cornerRadius = 15
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        card.addSubview(sendButton)

        configurePill(modeButton, action: #selector(modeTapped))
        configurePill(modelButton, action: #selector(modelTapped))

        textHeight = textView.heightAnchor.constraint(equalToConstant: minHeight)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: topAnchor),
            card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),

            textView.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            textView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            textView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            textHeight,

            placeholder.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            placeholder.topAnchor.constraint(equalTo: textView.topAnchor),

            plusButton.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            plusButton.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
            plusButton.widthAnchor.constraint(equalToConstant: 30),
            plusButton.heightAnchor.constraint(equalToConstant: 30),

            modeButton.leadingAnchor.constraint(equalTo: plusButton.trailingAnchor, constant: 8),
            modeButton.centerYAnchor.constraint(equalTo: plusButton.centerYAnchor),
            modeButton.heightAnchor.constraint(equalToConstant: 30),

            modelButton.leadingAnchor.constraint(equalTo: modeButton.trailingAnchor, constant: 8),
            modelButton.centerYAnchor.constraint(equalTo: plusButton.centerYAnchor),
            modelButton.heightAnchor.constraint(equalToConstant: 30),

            sendButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            sendButton.centerYAnchor.constraint(equalTo: plusButton.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 30),
            sendButton.heightAnchor.constraint(equalToConstant: 30),

            waveButton.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -10),
            waveButton.centerYAnchor.constraint(equalTo: plusButton.centerYAnchor),
            waveButton.widthAnchor.constraint(equalToConstant: 26),
            waveButton.heightAnchor.constraint(equalToConstant: 26),

            micButton.trailingAnchor.constraint(equalTo: waveButton.leadingAnchor, constant: -12),
            micButton.centerYAnchor.constraint(equalTo: plusButton.centerYAnchor),
            micButton.widthAnchor.constraint(equalToConstant: 26),
            micButton.heightAnchor.constraint(equalToConstant: 26),

            textView.bottomAnchor.constraint(equalTo: plusButton.topAnchor, constant: -12)
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsChanged),
            name: AppSettings.didChangeNotification,
            object: nil
        )

        refreshLabels()
        refreshState()
    }

    private func configureIconButton(_ button: UIButton, symbol: String, action: Selector) {
        button.setImage(UIImage(systemName: symbol), for: .normal)
        button.tintColor = Theme.textSecondary
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: action, for: .touchUpInside)
        card.addSubview(button)
    }

    private func configurePill(_ button: UIButton, action: Selector) {
        button.setTitleColor(Theme.textSecondary, for: .normal)
        button.titleLabel?.font = AppSettings.shared.chatFont.font(size: 13)
        button.backgroundColor = Theme.surfaceRaised
        button.layer.cornerRadius = 15
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: action, for: .touchUpInside)
        card.addSubview(button)
    }

    // MARK: - State

    func setStreaming(_ streaming: Bool) {
        isStreaming = streaming
        refreshState()
    }

    private func refreshState() {
        placeholder.isHidden = !(textView.text ?? "").isEmpty

        if isStreaming {
            sendButton.setImage(UIImage(systemName: "stop.fill"), for: .normal)
            sendButton.backgroundColor = Theme.surfaceRaised
            sendButton.tintColor = Theme.textPrimary
            sendButton.isEnabled = true
            return
        }

        let hasText = !(textView.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        sendButton.setImage(UIImage(systemName: "arrow.up"), for: .normal)
        sendButton.tintColor = hasText ? Theme.background : Theme.textTertiary
        sendButton.backgroundColor = hasText ? Theme.accent : Theme.surfaceRaised
        sendButton.isEnabled = hasText
    }

    func refreshLabels() {
        let settings = AppSettings.shared
        modeButton.setTitle(settings.mode.title, for: .normal)
        modelButton.setTitle(settings.selectedModel.name + "  " + settings.selectedModel.effort, for: .normal)

        textView.font = settings.chatFont.bodyFont()
        placeholder.font = settings.chatFont.bodyFont()
        modeButton.titleLabel?.font = settings.chatFont.font(size: 13)
        modelButton.titleLabel?.font = settings.chatFont.font(size: 13)

        modeButton.setTitleColor(
            settings.mode == .cowork ? Theme.accent : Theme.textSecondary,
            for: .normal
        )
    }

    @objc private func settingsChanged() {
        refreshLabels()
        recalculateHeight()
    }

    private func recalculateHeight() {
        let width = textView.bounds.width
        guard width > 0 else { return }

        let size = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let clamped = min(maxHeight, max(minHeight, size.height))

        guard abs(clamped - textHeight.constant) > 0.5 else { return }
        textHeight.constant = clamped
        textView.isScrollEnabled = clamped >= maxHeight
        delegate?.composerHeightChanged()
    }

    // MARK: - Actions

    @objc private func sendTapped() {
        if isStreaming {
            Haptics.tap()
            delegate?.composerDidTapStop()
            return
        }

        let value = (textView.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }

        Haptics.tap()
        textView.text = ""
        refreshState()
        recalculateHeight()
        delegate?.composerDidSend(value)
    }

    @objc private func plusTapped() {
        Haptics.tap()
        delegate?.composerDidTapPlus()
    }

    @objc private func modelTapped() {
        Haptics.tap()
        delegate?.composerDidTapModel()
    }

    @objc private func waveTapped() {
        Haptics.tap()
        delegate?.composerDidTapVoiceMode()
    }

    @objc private func modeTapped() {
        Haptics.tap()
        let next: ChatMode = AppSettings.shared.mode == .chat ? .cowork : .chat
        AppSettings.shared.mode = next
        refreshLabels()
        delegate?.composerDidChangeMode(next)
    }

    @objc private func micTapped() {
        if dictation.isRecording {
            dictation.stop()
            micButton.tintColor = Theme.textSecondary
            micButton.transform = .identity
            return
        }

        Haptics.tap()
        micButton.tintColor = Theme.accent

        dictation.start(
            onTranscript: { [weak self] transcript in
                self?.text = transcript
            },
            onLevel: { [weak self] level in
                guard let self = self, !AppSettings.shared.motionReduced else { return }
                let scale = 1 + CGFloat(level) * 0.35
                self.micButton.transform = CGAffineTransform(scaleX: scale, y: scale)
            },
            onError: { [weak self] error in
                guard let self = self else { return }
                self.micButton.tintColor = Theme.textSecondary
                self.micButton.transform = .identity
                Haptics.warning()

                let alert = UIAlertController(
                    title: "Dictation unavailable",
                    message: error.localizedDescription,
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                self.delegate?.composerNeedsPresenter().present(alert, animated: true, completion: nil)
            }
        )
    }

    func stopDictation() {
        dictation.stop()
        micButton.tintColor = Theme.textSecondary
        micButton.transform = .identity
    }

    override func becomeFirstResponder() -> Bool {
        textView.becomeFirstResponder()
    }
}

extension ComposerView: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        refreshState()
        recalculateHeight()
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
