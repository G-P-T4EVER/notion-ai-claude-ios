import UIKit

/// The main transcript screen.
final class ChatViewController: UIViewController {
    private let header = UIView()
    private let menuButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let newChatButton = UIButton(type: .system)
    private let table = UITableView(frame: .zero, style: .plain)
    private let composer = ComposerView()
    private let emptyState = EmptyStateView()

    private var conversation = ConversationStore.shared.create()
    private var stream: NotionAIStream?
    private var composerBottom: NSLayoutConstraint!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background

        buildHeader()
        buildTable()
        buildComposer()
        buildEmptyState()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsChanged),
            name: AppSettings.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChange(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )

        refresh()
    }

    // MARK: - Layout

    private func buildHeader() {
        header.backgroundColor = Theme.background
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)

        menuButton.setImage(UIImage(systemName: "line.3.horizontal"), for: .normal)
        if menuButton.image(for: .normal) == nil {
            menuButton.setImage(UIImage(systemName: "line.horizontal.3"), for: .normal)
        }
        menuButton.tintColor = Theme.textSecondary
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        menuButton.addTarget(self, action: #selector(menuTapped), for: .touchUpInside)
        header.addSubview(menuButton)

        titleLabel.textColor = Theme.textPrimary
        titleLabel.font = AppSettings.shared.chatFont.font(size: 16, weight: .medium)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(titleLabel)

        newChatButton.setImage(UIImage(systemName: "square.and.pencil"), for: .normal)
        newChatButton.tintColor = Theme.textSecondary
        newChatButton.translatesAutoresizingMaskIntoConstraints = false
        newChatButton.addTarget(self, action: #selector(newChatTapped), for: .touchUpInside)
        header.addSubview(newChatButton)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 48),

            menuButton.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            menuButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            menuButton.widthAnchor.constraint(equalToConstant: 32),
            menuButton.heightAnchor.constraint(equalToConstant: 32),

            newChatButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
            newChatButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            newChatButton.widthAnchor.constraint(equalToConstant: 32),
            newChatButton.heightAnchor.constraint(equalToConstant: 32),

            titleLabel.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: menuButton.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: newChatButton.leadingAnchor, constant: -8)
        ])
    }

    private func buildTable() {
        table.backgroundColor = Theme.background
        table.separatorStyle = .none
        table.dataSource = self
        table.delegate = self
        table.keyboardDismissMode = .interactive
        table.estimatedRowHeight = 96
        table.rowHeight = UITableView.automaticDimension
        table.contentInset = UIEdgeInsets(top: 8, left: 0, bottom: 12, right: 0)
        table.register(UserMessageCell.self, forCellReuseIdentifier: UserMessageCell.reuseID)
        table.register(AssistantMessageCell.self, forCellReuseIdentifier: AssistantMessageCell.reuseID)
        table.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(table)
    }

    private func buildComposer() {
        composer.delegate = self
        composer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(composer)

        composerBottom = composer.bottomAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.bottomAnchor,
            constant: -8
        )

        NSLayoutConstraint.activate([
            composer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            composer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            composerBottom,

            table.topAnchor.constraint(equalTo: header.bottomAnchor),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: composer.topAnchor, constant: -6)
        ])
    }

    private func buildEmptyState() {
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        emptyState.onPick = { [weak self] action in
            self?.handle(action)
        }
        view.addSubview(emptyState)

        NSLayoutConstraint.activate([
            emptyState.topAnchor.constraint(equalTo: header.bottomAnchor),
            emptyState.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyState.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyState.bottomAnchor.constraint(equalTo: composer.topAnchor)
        ])
    }

    // MARK: - Conversation plumbing

    func loadConversation(_ id: String?) {
        stream?.cancel()
        stream = nil
        composer.setStreaming(false)
        composer.stopDictation()

        if let id = id, let existing = ConversationStore.shared.conversation(withID: id) {
            conversation = existing
        } else if conversation.messages.isEmpty {
            // Reuse the current empty chat instead of piling up blank ones.
            conversation.mode = AppSettings.shared.mode
            conversation.modelID = AppSettings.shared.selectedModel.id
        } else {
            conversation = ConversationStore.shared.create()
        }

        AppSettings.shared.mode = conversation.mode
        table.reloadData()
        refresh()
        scrollToBottom(animated: false)
    }

    func prefill(_ text: String) {
        composer.text = text
        _ = composer.becomeFirstResponder()
    }

    private func refresh() {
        titleLabel.text = conversation.messages.isEmpty ? "Notion AI" : conversation.title
        emptyState.isHidden = !conversation.messages.isEmpty
        composer.refreshLabels()
    }

    private func persist() {
        ConversationStore.shared.save(conversation)
        refresh()
    }

    private func scrollToBottom(animated: Bool) {
        guard !conversation.messages.isEmpty else { return }
        let indexPath = IndexPath(row: conversation.messages.count - 1, section: 0)
        table.scrollToRow(at: indexPath, at: .bottom, animated: animated && !AppSettings.shared.motionReduced)
    }

    private func refreshLastRow() {
        guard !conversation.messages.isEmpty else { return }
        let indexPath = IndexPath(row: conversation.messages.count - 1, section: 0)

        UIView.performWithoutAnimation {
            table.reloadRows(at: [indexPath], with: .none)
        }
        scrollToBottom(animated: false)
    }

    // MARK: - Sending

    private func send(_ text: String) {
        guard NotionSession.shared.isAuthenticated else {
            presentSessionExpired()
            return
        }

        conversation.messages.append(ChatMessage.user(text))
        conversation.messages.append(ChatMessage.assistantPlaceholder())
        conversation.modelID = AppSettings.shared.selectedModel.id
        conversation.mode = AppSettings.shared.mode
        persist()

        table.reloadData()
        scrollToBottom(animated: true)
        composer.setStreaming(true)

        if AppSettings.shared.mode == .cowork {
            groundInWorkspace(question: text) { [weak self] context in
                self?.beginStream(workspaceContext: context)
            }
        } else {
            beginStream(workspaceContext: nil)
        }
    }

    /// Cowork mode: search the workspace first and hand the hits to the model.
    private func groundInWorkspace(question: String, completion: @escaping (String?) -> Void) {
        appendActivity(ActivityNote(symbol: "magnifyingglass", text: "Searching your workspace"))

        NotionAPI.shared.search(query: question, limit: 8) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .failure:
                completion(nil)

            case .success(let pages):
                guard !pages.isEmpty else {
                    completion(nil)
                    return
                }

                self.appendActivity(
                    ActivityNote(
                        symbol: "doc.text",
                        text: "Found " + String(pages.count) + " pages"
                    )
                )

                let context = pages.map { page in
                    "- " + page.title + " (" + page.url + ")" +
                        (page.snippet.isEmpty ? "" : ": " + page.snippet)
                }.joined(separator: "\n")

                completion("Relevant pages from the user's Notion workspace:\n" + context)
            }
        }
    }

    private func appendActivity(_ note: ActivityNote) {
        guard let index = conversation.messages.indices.last else { return }
        guard conversation.messages[index].role == .assistant else { return }
        guard !conversation.messages[index].activity.contains(note) else { return }

        conversation.messages[index].activity.append(note)
        refreshLastRow()
    }

    private func beginStream(workspaceContext: String?) {
        let history = conversation.messages.filter { !($0.role == .assistant && $0.text.isEmpty) }

        let request = NotionAIStream.Request(
            messages: history,
            mode: AppSettings.shared.mode,
            model: AppSettings.shared.selectedModel,
            conversationID: conversation.id,
            workspaceContext: workspaceContext
        )

        let stream = NotionAIStream()
        self.stream = stream

        stream.start(
            request,
            onDelta: { [weak self] delta in
                guard let self = self, let index = self.conversation.messages.indices.last else { return }
                self.conversation.messages[index].text += delta
                self.refreshLastRow()
            },
            onActivity: { [weak self] note in
                self?.appendActivity(note)
            },
            onFinish: { [weak self] result in
                guard let self = self else { return }
                guard let index = self.conversation.messages.indices.last else { return }

                self.composer.setStreaming(false)
                self.conversation.messages[index].isStreaming = false

                switch result {
                case .success(let text):
                    if !text.isEmpty {
                        self.conversation.messages[index].text = text
                    }
                    Haptics.success()

                case .failure(let error):
                    self.conversation.messages[index].failed = true
                    self.conversation.messages[index].text = error.localizedDescription
                    Haptics.warning()

                    if case NotionError.sessionExpired = error {
                        self.presentSessionExpired()
                    }
                }

                self.persist()
                self.refreshLastRow()
            }
        )
    }

    private func retryLastTurn() {
        guard let lastUser = conversation.messages.last(where: { $0.role == .user })?.text else { return }

        while let last = conversation.messages.last, last.role == .assistant {
            conversation.messages.removeLast()
        }
        if conversation.messages.last?.role == .user {
            conversation.messages.removeLast()
        }

        table.reloadData()
        send(lastUser)
    }

    // MARK: - Actions

    @objc private func menuTapped() {
        Haptics.tap()
        RootController.current?.toggleSidebar()
    }

    @objc private func newChatTapped() {
        Haptics.tap()
        loadConversation(nil)
    }

    @objc private func settingsChanged() {
        titleLabel.font = AppSettings.shared.chatFont.font(size: 16, weight: .medium)
        emptyState.refreshFonts()
        composer.refreshLabels()
        table.reloadData()
    }

    private func handle(_ action: QuickAction) {
        if action.title == "Claude's choice" {
            send(action.prompt)
        } else {
            prefill(action.prompt)
        }
    }

    private func presentSessionExpired() {
        let alert = UIAlertController(
            title: "Session expired",
            message: "Sign in to Notion again to keep chatting.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Sign in", style: .default) { _ in
            NotionSession.shared.signOut()
        })
        alert.addAction(UIAlertAction(title: "Later", style: .cancel, handler: nil))
        present(alert, animated: true, completion: nil)
    }

    // MARK: - Keyboard

    @objc private func keyboardWillChange(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else { return }

        let height = view.convert(frame.cgRectValue, from: nil).height
        let inset = max(0, height - view.safeAreaInsets.bottom)
        composerBottom.constant = -8 - inset

        let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        UIView.animate(withDuration: AppSettings.shared.motionReduced ? 0 : duration) {
            self.view.layoutIfNeeded()
        }
        scrollToBottom(animated: false)
    }

    @objc private func keyboardWillHide() {
        composerBottom.constant = -8
        UIView.animate(withDuration: AppSettings.shared.motionReduced ? 0 : 0.22) {
            self.view.layoutIfNeeded()
        }
    }
}

// MARK: - Table

extension ChatViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        conversation.messages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let message = conversation.messages[indexPath.row]

        switch message.role {
        case .user:
            let cell = tableView.dequeueReusableCell(
                withIdentifier: UserMessageCell.reuseID,
                for: indexPath
            ) as! UserMessageCell
            cell.configure(with: message)
            return cell

        case .assistant:
            let cell = tableView.dequeueReusableCell(
                withIdentifier: AssistantMessageCell.reuseID,
                for: indexPath
            ) as! AssistantMessageCell
            cell.configure(with: message)
            return cell
        }
    }

    func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        let message = conversation.messages[indexPath.row]

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            let copy = UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { _ in
                UIPasteboard.general.string = Markdown.plainText(message.text)
                Haptics.success()
            }
            let retry = UIAction(title: "Retry", image: UIImage(systemName: "arrow.clockwise")) { [weak self] _ in
                self?.retryLastTurn()
            }
            return UIMenu(title: "", children: [copy, retry])
        }
    }
}

// MARK: - Composer

extension ChatViewController: ComposerViewDelegate {
    func composerDidSend(_ text: String) {
        send(text)
    }

    func composerDidTapStop() {
        stream?.cancel()
        stream = nil
        composer.setStreaming(false)

        if let index = conversation.messages.indices.last {
            conversation.messages[index].isStreaming = false
            if conversation.messages[index].text.isEmpty {
                conversation.messages[index].text = "Stopped."
            }
        }
        persist()
        refreshLastRow()
    }

    func composerDidTapPlus() {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        sheet.addAction(UIAlertAction(title: "Browse workspace", style: .default) { _ in
            RootController.current?.presentWorkspace()
        })
        sheet.addAction(UIAlertAction(title: "Reference a page", style: .default) { [weak self] _ in
            self?.presentPagePicker()
        })
        sheet.addAction(UIAlertAction(title: "Skills", style: .default) { _ in
            RootController.current?.presentSettings(initialSection: .skills)
        })
        sheet.addAction(UIAlertAction(title: "Connectors", style: .default) { _ in
            RootController.current?.presentSettings(initialSection: .connectors)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(sheet, animated: true, completion: nil)
    }

    private func presentPagePicker() {
        let picker = WorkspaceViewController()
        picker.onPick = { [weak self] page in
            guard let self = self else { return }
            let current = self.composer.text
            let reference = "[" + page.title + "](" + page.url + ") "
            self.composer.text = current.isEmpty ? reference : current + " " + reference
        }
        present(UINavigationController(rootViewController: picker), animated: true, completion: nil)
    }

    func composerDidTapModel() {
        let sheet = UIAlertController(title: "Model", message: nil, preferredStyle: .actionSheet)

        for model in AIModel.all {
            let selected = model == AppSettings.shared.selectedModel
            let title = (selected ? "\u{2713}  " : "") + model.name + " \u{00B7} " + model.effort
            sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                AppSettings.shared.selectedModel = model
                self?.composer.refreshLabels()
            })
        }

        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(sheet, animated: true, completion: nil)
    }

    func composerDidChangeMode(_ mode: ChatMode) {
        conversation.mode = mode

        let banner = UIAlertController(title: mode.title, message: mode.hint, preferredStyle: .alert)
        banner.addAction(UIAlertAction(title: "Got it", style: .default, handler: nil))
        present(banner, animated: true, completion: nil)
    }

    func composerDidTapVoiceMode() {
        let alert = UIAlertController(
            title: "Voice mode",
            message: "Hold the mic to dictate. Full duplex voice needs a Notion realtime endpoint, which is not public yet.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }

    func composerHeightChanged() {
        view.layoutIfNeeded()
        scrollToBottom(animated: false)
    }

    func composerNeedsPresenter() -> UIViewController {
        self
    }
}
