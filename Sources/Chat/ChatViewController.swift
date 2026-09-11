import UIKit

final class ChatViewController: UIViewController {
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let composer = ComposerView()
    private let emptyState = EmptyStateView()

    private var conversation = ConversationStore.shared.create()
    private let stream = NotionAIStream()
    private var streamingIndex: Int?
    private var composerBottom: NSLayoutConstraint!
    private var lastFailedPrompt: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.keyboardDismissMode = .interactive
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 90
        tableView.contentInset = UIEdgeInsets(top: 8, left: 0, bottom: 12, right: 0)
        tableView.register(UserMessageCell.self, forCellReuseIdentifier: UserMessageCell.reuseID)
        tableView.register(AssistantMessageCell.self, forCellReuseIdentifier: AssistantMessageCell.reuseID)
        view.addSubview(tableView)

        emptyState.translatesAutoresizingMaskIntoConstraints = false
        emptyState.onPick = { [weak self] action in
            self?.composer.text = action.prompt
        }
        view.addSubview(emptyState)

        composer.translatesAutoresizingMaskIntoConstraints = false
        composer.delegate = self
        view.addSubview(composer)

        composerBottom = composer.bottomAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.bottomAnchor,
            constant: -8
        )

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: composer.topAnchor, constant: -6),

            emptyState.topAnchor.constraint(equalTo: view.topAnchor),
            emptyState.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyState.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyState.bottomAnchor.constraint(equalTo: composer.topAnchor),

            composer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            composer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            composerBottom
        ])

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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsChanged),
            name: AppSettings.didChangeNotification,
            object: nil
        )

        refreshState()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Feedback.prepare()
        if conversation.messages.isEmpty {
            emptyState.refreshGreeting()
        }
    }

    // MARK: - Conversation plumbing

    func loadConversation(_ id: String?) {
        stream.cancel()
        streamingIndex = nil
        composer.setStreaming(false)

        if let id = id, let existing = ConversationStore.shared.conversation(withID: id) {
            conversation = existing
        } else {
            conversation = ConversationStore.shared.create()
            if
                let agentID = AppSettings.shared.defaultAgentID,
                let agent = LibraryStore.shared.agent(withID: agentID)
            {
                conversation.agentID = agent.id
                conversation.modelID = agent.modelID
                conversation.effort = agent.effort
            }
        }

        tableView.reloadData()
        refreshState()
        if conversation.messages.isEmpty {
            emptyState.refreshGreeting()
        } else {
            scrollToBottom(animated: false)
        }
    }

    func prefill(_ text: String) {
        composer.text = text
        composer.becomeFirstResponder()
    }

    private func refreshState() {
        let empty = conversation.messages.isEmpty
        emptyState.isHidden = !empty
        tableView.isHidden = empty
        composer.refreshLabels()
    }

    @objc private func settingsChanged() {
        composer.refreshLabels()
        emptyState.refreshFonts()
        tableView.reloadData()
    }

    private func scrollToBottom(animated: Bool) {
        guard !conversation.messages.isEmpty else { return }
        let indexPath = IndexPath(row: conversation.messages.count - 1, section: 0)
        tableView.scrollToRow(at: indexPath, at: .bottom, animated: animated)
    }

    private func persist() {
        conversation.updatedAt = Date()
        conversation.retitleIfNeeded()
        ConversationStore.shared.save(conversation)
    }

    // MARK: - Prompt assembly

    private func systemPrompt() -> String {
        var parts: [String] = []

        if let agent = conversation.agentID.flatMap({ LibraryStore.shared.agent(withID: $0) }) {
            parts.append("You are acting as the agent \"\(agent.name)\".")
            parts.append(agent.instructions)
            parts.append("Tone: \(agent.tone).")
        }

        let skills = LibraryStore.shared.activeSkills
        if !skills.isEmpty {
            let lines = skills.map { "- \($0.name): \($0.prompt)" }.joined(separator: "\n")
            parts.append("Active skills:\n" + lines)
        }

        let connectors = AppSettings.shared.enabledConnectorIDs
            .compactMap { Connector.connector(for: $0)?.name }
        if !connectors.isEmpty {
            parts.append("Connected services: " + connectors.joined(separator: ", ") + ".")
        }

        let memory = LibraryStore.shared.memoryDigest()
        if !memory.isEmpty {
            parts.append("Known facts about the user:\n" + memory)
        }

        if AppSettings.shared.mode == .cowork {
            parts.append("Cowork mode: propose concrete page edits and next actions.")
        }

        return parts.joined(separator: "\n\n")
    }

    // MARK: - Sending

    private func send(_ text: String) {
        if AppSettings.shared.isQuietTimeNow {
            let alert = UIAlertController(
                title: "Quiet hours are on",
                message: "Notion AI is muted right now. Send anyway?",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
                self?.composer.text = text
            })
            alert.addAction(UIAlertAction(title: "Send", style: .default) { [weak self] _ in
                self?.dispatch(text)
            })
            present(alert, animated: true)
            return
        }
        dispatch(text)
    }

    private func dispatch(_ text: String) {
        lastFailedPrompt = nil
        let settings = AppSettings.shared
        let model = AIModel.model(for: conversation.modelID == AIModel.default.id
            ? settings.selectedModel.id
            : conversation.modelID)
        let effort = settings.effort

        conversation.modelID = model.id
        conversation.effort = effort
        conversation.mode = settings.mode
        conversation.skillIDs = settings.activeSkillIDs

        conversation.messages.append(.user(text))
        conversation.messages.append(.assistantPlaceholder(modelID: model.id))
        streamingIndex = conversation.messages.count - 1

        refreshState()
        tableView.reloadData()
        scrollToBottom(animated: true)
        composer.setStreaming(true)
        persist()

        let messages = conversation.messages.filter { !$0.isStreaming }

        NotionAPI.shared.contextSnippet(for: text) { [weak self] context in
            guard let self = self else { return }
            let request = NotionAIStream.Request(
                messages: messages,
                mode: self.conversation.mode,
                model: model,
                effort: effort,
                conversationID: self.conversation.id,
                workspaceContext: context,
                systemPrompt: self.systemPrompt()
            )

            self.stream.start(
                request,
                onDelta: { [weak self] delta in
                    self?.appendDelta(delta)
                },
                onActivity: { [weak self] note in
                    self?.appendActivity(note)
                },
                onProgress: { [weak self] progress in
                    self?.updateProgress(progress)
                },
                onFinish: { [weak self] result in
                    self?.finishStream(result, prompt: text)
                }
            )
        }
    }

    private func appendDelta(_ delta: String) {
        guard let index = streamingIndex, index < conversation.messages.count else { return }
        conversation.messages[index].text += delta
        conversation.messages[index].progress = nil
        reloadStreamingRow(index)
    }

    private func updateProgress(_ progress: String) {
        guard let index = streamingIndex, index < conversation.messages.count else { return }
        guard conversation.messages[index].text.isEmpty else { return }
        conversation.messages[index].progress = progress
        reloadStreamingRow(index)
    }

    private func appendActivity(_ note: ActivityNote) {
        guard let index = streamingIndex, index < conversation.messages.count else { return }
        guard !conversation.messages[index].activity.contains(note) else { return }
        conversation.messages[index].activity.append(note)
        reloadStreamingRow(index)
    }

    private func reloadStreamingRow(_ index: Int) {
        let indexPath = IndexPath(row: index, section: 0)
        guard tableView.numberOfRows(inSection: 0) > index else {
            tableView.reloadData()
            return
        }
        UIView.performWithoutAnimation {
            tableView.reloadRows(at: [indexPath], with: .none)
        }
        let isNearBottom = tableView.contentOffset.y
            >= tableView.contentSize.height - tableView.bounds.height - 140
        if isNearBottom { scrollToBottom(animated: false) }
    }

    private func finishStream(_ result: Result<String, Error>, prompt: String) {
        composer.setStreaming(false)
        guard let index = streamingIndex, index < conversation.messages.count else { return }
        streamingIndex = nil
        conversation.messages[index].isStreaming = false
        conversation.messages[index].progress = nil

        switch result {
        case .success(let text):
            conversation.messages[index].text = text
            Feedback.success()
        case .failure(let error):
            conversation.messages[index].failed = true
            conversation.messages[index].text = errorText(for: error)
            lastFailedPrompt = prompt
            Feedback.error()
            presentFailure(error)
        }

        tableView.reloadData()
        scrollToBottom(animated: true)
        persist()
    }

    private func errorText(for error: Error) -> String {
        if let notionError = error as? NotionError {
            switch notionError {
            case .sessionExpired:
                return "Your Notion session expired. Sign in again from Settings → Account."
            case .notAuthenticated:
                return "Not signed in to Notion."
            case .http(let code):
                return "Notion AI refused the request (HTTP \(code)). Try a different endpoint path in Settings → Capabilities."
            case .endpointUnavailable(let detail):
                return "Notion AI replied in an unexpected shape:\n\n" + detail
            case .transport(let detail):
                return "Network problem: " + detail
            case .malformedResponse:
                return "Notion AI sent a response this build could not parse. Open Settings → Capabilities → Last response to see the raw payload."
            }
        }
        return error.localizedDescription
    }

    private func presentFailure(_ error: Error) {
        let alert = UIAlertController(
            title: "Request failed",
            message: errorText(for: error),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Close", style: .cancel))
        if let prompt = lastFailedPrompt {
            alert.addAction(UIAlertAction(title: "Retry", style: .default) { [weak self] _ in
                guard let self = self else { return }
                if !self.conversation.messages.isEmpty { self.conversation.messages.removeLast() }
                if !self.conversation.messages.isEmpty { self.conversation.messages.removeLast() }
                self.dispatch(prompt)
            })
        }
        alert.addAction(UIAlertAction(title: "Diagnostics", style: .default) { _ in
            RootController.current?.presentSettings(initialSection: .capabilities)
        })
        present(alert, animated: true)
    }

    // MARK: - Keyboard

    @objc private func keyboardWillChange(_ note: Notification) {
        guard
            let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue,
            let duration = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
        else { return }

        let overlap = max(0, view.bounds.maxY - frame.minY - view.safeAreaInsets.bottom)
        composerBottom.constant = -8 - overlap
        UIView.animate(withDuration: duration) { self.view.layoutIfNeeded() }
    }

    @objc private func keyboardWillHide() {
        composerBottom.constant = -8
        UIView.animate(withDuration: 0.2) { self.view.layoutIfNeeded() }
    }
}

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
                Feedback.success()
            }
            return UIMenu(title: "", children: [copy])
        }
    }
}

extension ChatViewController: ComposerViewDelegate {
    func composerDidSend(_ text: String) {
        send(text)
    }

    func composerDidTapStop() {
        stream.cancel()
        composer.setStreaming(false)
        if let index = streamingIndex, index < conversation.messages.count {
            conversation.messages[index].isStreaming = false
            conversation.messages[index].progress = nil
            if conversation.messages[index].text.isEmpty {
                conversation.messages[index].text = "Stopped."
            }
            tableView.reloadData()
            persist()
        }
        streamingIndex = nil
    }

    func composerDidTapPlus() {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Search workspace", style: .default) { _ in
            RootController.current?.presentWorkspace()
        })
        sheet.addAction(UIAlertAction(title: "Skills", style: .default) { [weak self] _ in
            self?.composerDidTapSkills()
        })
        sheet.addAction(UIAlertAction(title: "Agents", style: .default) { _ in
            RootController.current?.presentSettings(initialSection: .agents)
        })
        sheet.addAction(UIAlertAction(title: "Connectors", style: .default) { _ in
            RootController.current?.presentSettings(initialSection: .connectors)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet.popoverPresentationController?.sourceView = composer
        sheet.popoverPresentationController?.sourceRect = composer.bounds
        present(sheet, animated: true)
    }

    func composerDidTapModel() {
        let settings = AppSettings.shared
        let picker = ModelPickerViewController(model: settings.selectedModel, effort: settings.effort)
        picker.onChange = { [weak self] model, effort in
            settings.selectedModel = model
            settings.effort = effort
            self?.conversation.modelID = model.id
            self?.conversation.effort = effort
            self?.composer.refreshLabels()
            self?.emptyState.refreshGreeting()
        }
        let navigation = UINavigationController(rootViewController: picker)
        Feedback.sheet()
        present(navigation, animated: true)
    }

    func composerDidTapSkills() {
        let skills = SkillsViewController(pickMode: true)
        skills.onPick = { [weak self] skill in
            guard let self = self else { return }
            let existing = self.composer.text.trimmingCharacters(in: .whitespacesAndNewlines)
            self.composer.text = existing.isEmpty
                ? skill.prompt + " "
                : existing + "\n\n" + skill.prompt + " "
            self.composer.becomeFirstResponder()
        }
        let navigation = UINavigationController(rootViewController: skills)
        Feedback.sheet()
        present(navigation, animated: true)
    }

    func composerDidChangeMode(_ mode: ChatMode) {
        conversation.mode = mode
        emptyState.refreshGreeting()
    }

    func composerHeightChanged() {
        view.layoutIfNeeded()
        guard !conversation.messages.isEmpty else { return }
        scrollToBottom(animated: false)
    }

    func composerNeedsPresenter() -> UIViewController {
        self
    }
}
