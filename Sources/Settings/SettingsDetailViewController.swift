import UIKit

final class SettingsDetailViewController: UIViewController {
    private let section: SettingsSection
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var blocks: [SettingsBlock] = []

    init(section: SettingsSection) {
        self.section = section
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        title = section.title

        if embedChildIfNeeded() { return }

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = Theme.background
        tableView.separatorColor = Theme.border
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 56
        view.addSubview(tableView)
        tableView.pinEdges(to: view)

        if section == .reflect {
            let header = ReflectHeaderView(
                frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 430)
            )
            tableView.tableHeaderView = header
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(rebuild),
            name: NotionSession.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(rebuild),
            name: LibraryStore.didChangeNotification,
            object: nil
        )

        rebuild()
        if section == .account { refreshProfile(silent: true) }
    }

    /// Sections that are full screens of their own are embedded as children so
    /// the settings list keeps one push style everywhere.
    private func embedChildIfNeeded() -> Bool {
        let child: UIViewController?
        switch section {
        case .agents: child = AgentsViewController()
        case .skills: child = SkillsViewController(pickMode: false)
        case .connectors: child = ConnectorsViewController()
        default: child = nil
        }
        guard let controller = child else { return false }

        addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controller.view)
        controller.view.pinEdges(to: view)
        controller.didMove(toParent: self)
        navigationItem.rightBarButtonItem = controller.navigationItem.rightBarButtonItem
        return true
    }

    // MARK: - Content

    @objc private func rebuild() {
        blocks = makeBlocks()
        tableView.reloadData()
    }

    private func makeBlocks() -> [SettingsBlock] {
        let settings = AppSettings.shared

        switch section {
        case .general:
            let fontRows = ChatFontChoice.allCases.map { choice in
                SettingsRow(
                    title: choice.title,
                    subtitle: nil,
                    accessory: .checkmark(settings.chatFont == choice),
                    action: { [weak self] in
                        settings.chatFont = choice
                        Feedback.selection()
                        self?.rebuild()
                    }
                )
            }

            let hapticRows = HapticStrength.allCases.map { strength in
                SettingsRow(
                    title: strength.title,
                    subtitle: strength.detail,
                    accessory: .checkmark(settings.hapticStrength == strength),
                    action: { [weak self] in
                        settings.hapticStrength = strength
                        Feedback.success()
                        self?.rebuild()
                    }
                )
            }

            return [
                SettingsBlock(header: "CHAT FONT", footer: nil, rows: fontRows),
                SettingsBlock(header: "MOTION", footer: "Turn motion off to remove sidebar and streaming animations.", rows: [
                    SettingsRow(
                        title: "Motion",
                        subtitle: nil,
                        accessory: .toggle(!settings.reduceMotion) { isOn in
                            settings.reduceMotion = !isOn
                            Feedback.toggle(isOn)
                        }
                    )
                ]),
                SettingsBlock(header: "HAPTICS", footer: "Haptic feedback fires on sends, toggles, model changes and sheet transitions.", rows: hapticRows),
                SettingsBlock(header: "COMPOSER", footer: nil, rows: [
                    SettingsRow(
                        title: "Return key sends",
                        subtitle: nil,
                        accessory: .toggle(settings.sendOnReturn) { isOn in
                            settings.sendOnReturn = isOn
                            Feedback.toggle(isOn)
                        }
                    )
                ])
            ]

        case .account:
            let session = NotionSession.shared
            let name = session.userName?.isEmpty == false ? session.userName! : "Loading…"
            let email = session.userEmail?.isEmpty == false ? session.userEmail! : "Loading…"
            let space = session.spaceName?.isEmpty == false ? session.spaceName! : "Loading…"

            return [
                SettingsBlock(header: "SIGNED IN AS", footer: "Details come from your Notion account, so they change when you switch workspace.", rows: [
                    SettingsRow(title: "Name", subtitle: nil, accessory: .value(name)),
                    SettingsRow(title: "Email", subtitle: nil, accessory: .value(email)),
                    SettingsRow(title: "Workspace", subtitle: nil, accessory: .value(space)),
                    SettingsRow(title: "Refresh details", subtitle: nil, accessory: .disclosure, action: { [weak self] in
                        self?.refreshProfile(silent: false)
                    }),
                    SettingsRow(title: "Switch workspace", subtitle: nil, accessory: .disclosure, action: { [weak self] in
                        self?.presentSwitcher()
                    })
                ]),
                SettingsBlock(header: nil, footer: nil, rows: [
                    SettingsRow(title: "Sign out", subtitle: nil, destructive: true, action: { [weak self] in
                        self?.confirmSignOut()
                    })
                ])
            ]

        case .privacy:
            return [
                SettingsBlock(header: "DATA", footer: "Chats, skills, agents and imported memories live only on this device.", rows: [
                    SettingsRow(
                        title: "Share usage analytics",
                        subtitle: nil,
                        accessory: .toggle(!settings.analyticsOptOut) { isOn in
                            settings.analyticsOptOut = !isOn
                            Feedback.toggle(isOn)
                        }
                    )
                ]),
                SettingsBlock(header: nil, footer: nil, rows: [
                    SettingsRow(title: "Delete all chats", subtitle: nil, destructive: true, action: { [weak self] in
                        self?.confirmDeleteChats()
                    })
                ])
            ]

        case .billing:
            let plans = PlanTier.allCases.map { tier in
                SettingsRow(
                    title: tier.title,
                    subtitle: AIModel.models(in: tier).map { $0.name }.joined(separator: ", "),
                    accessory: .none
                )
            }
            return [
                SettingsBlock(header: "MODELS BY PLAN", footer: "Model availability follows your Notion plan. If a model is not in your plan, Notion AI answers with your plan's best model instead.", rows: plans),
                SettingsBlock(header: nil, footer: nil, rows: [
                    SettingsRow(title: "Manage plan in Notion", subtitle: nil, accessory: .disclosure, action: {
                        guard let url = URL(string: NotionEndpoints.host + "/settings/plans") else { return }
                        Feedback.tap()
                        UIApplication.shared.open(url)
                    })
                ])
            ]

        case .capabilities:
            return [
                SettingsBlock(header: "MODEL", footer: nil, rows: [
                    SettingsRow(
                        title: "Model",
                        subtitle: settings.selectedModel.blurb,
                        accessory: .value(settings.selectedModel.name),
                        action: { [weak self] in self?.presentModelPicker() }
                    ),
                    SettingsRow(
                        title: "Effort",
                        subtitle: settings.effort.detail,
                        accessory: .value(settings.effort.title),
                        action: { [weak self] in self?.presentModelPicker() }
                    )
                ]),
                SettingsBlock(header: "AI ENDPOINT", footer: "Notion's AI endpoint is private and changes over time. If answers stop arriving, try another path.", rows: [
                    SettingsRow(
                        title: "Endpoint path",
                        subtitle: "api/v3/" + settings.aiEndpointPath,
                        accessory: .disclosure,
                        action: { [weak self] in self?.editEndpoint() }
                    )
                ]),
                SettingsBlock(header: "DIAGNOSTICS", footer: settings.lastRequestInfo.isEmpty ? nil : "Last request: " + settings.lastRequestInfo, rows: [
                    SettingsRow(
                        title: "Verbose diagnostics",
                        subtitle: nil,
                        accessory: .toggle(settings.diagnosticsEnabled) { isOn in
                            settings.diagnosticsEnabled = isOn
                            Feedback.toggle(isOn)
                        }
                    ),
                    SettingsRow(
                        title: "Last response",
                        subtitle: settings.lastRawResponse.isEmpty ? "Nothing captured yet" : "Raw payload from Notion",
                        accessory: .disclosure,
                        action: { [weak self] in
                            Feedback.tap()
                            self?.navigationController?.pushViewController(
                                RawResponseViewController(),
                                animated: true
                            )
                        }
                    )
                ])
            ]

        case .memory:
            let store = LibraryStore.shared
            let sources = store.memorySources()
                .map { "\($0.source) · \($0.count)" }
                .joined(separator: "\n")

            return [
                SettingsBlock(header: "MEMORY", footer: "Stored facts are attached to every request so answers stay consistent.", rows: [
                    SettingsRow(
                        title: "Use memory",
                        subtitle: nil,
                        accessory: .toggle(settings.memoryEnabled) { isOn in
                            settings.memoryEnabled = isOn
                            Feedback.toggle(isOn)
                        }
                    ),
                    SettingsRow(
                        title: "Stored facts",
                        subtitle: sources.isEmpty ? nil : sources,
                        accessory: .value("\(store.memories.count)")
                    )
                ]),
                SettingsBlock(header: "IMPORT", footer: "Bring memory over from ChatGPT, Claude, Gemini or Grok exports.", rows: [
                    SettingsRow(title: "Import from another assistant", subtitle: nil, accessory: .disclosure, action: { [weak self] in
                        Feedback.tap()
                        self?.navigationController?.pushViewController(
                            SettingsDetailViewController(section: .connectors),
                            animated: true
                        )
                    }),
                    SettingsRow(title: "Add a fact manually", subtitle: nil, accessory: .disclosure, action: { [weak self] in
                        self?.addMemory()
                    })
                ]),
                SettingsBlock(header: nil, footer: nil, rows: [
                    SettingsRow(title: "Clear memory", subtitle: nil, destructive: true, action: {
                        LibraryStore.shared.clearMemories()
                        Feedback.warning()
                    })
                ])
            ]

        case .reflect:
            return []

        case .timeAndFocus:
            return [
                SettingsBlock(header: "QUIET HOURS", footer: "Decide when Notion AI is off. During quiet hours the app asks before sending.", rows: [
                    SettingsRow(
                        title: "Quiet hours",
                        subtitle: nil,
                        accessory: .toggle(settings.quietHoursEnabled) { isOn in
                            settings.quietHoursEnabled = isOn
                            Feedback.toggle(isOn)
                        }
                    ),
                    SettingsRow(
                        title: "Start",
                        subtitle: nil,
                        accessory: .value(String(format: "%02d:00", settings.quietHoursStart)),
                        action: { [weak self] in self?.pickHour(isStart: true) }
                    ),
                    SettingsRow(
                        title: "End",
                        subtitle: nil,
                        accessory: .value(String(format: "%02d:00", settings.quietHoursEnd)),
                        action: { [weak self] in self?.pickHour(isStart: false) }
                    )
                ])
            ]

        case .plugins:
            return [
                SettingsBlock(header: "PLUGINS", footer: "Plugins are a desktop-only surface in Notion today. Skills, agents and connectors cover the same ground in this build.", rows: [
                    SettingsRow(title: "Skills", subtitle: "\(LibraryStore.shared.skills.count) available", accessory: .disclosure, action: { [weak self] in
                        Feedback.tap()
                        self?.navigationController?.pushViewController(
                            SettingsDetailViewController(section: .skills),
                            animated: true
                        )
                    }),
                    SettingsRow(title: "Agents", subtitle: "\(LibraryStore.shared.agents.count) configured", accessory: .disclosure, action: { [weak self] in
                        Feedback.tap()
                        self?.navigationController?.pushViewController(
                            SettingsDetailViewController(section: .agents),
                            animated: true
                        )
                    }),
                    SettingsRow(title: "Connectors", subtitle: "\(AppSettings.shared.enabledConnectorIDs.count) enabled", accessory: .disclosure, action: { [weak self] in
                        Feedback.tap()
                        self?.navigationController?.pushViewController(
                            SettingsDetailViewController(section: .connectors),
                            animated: true
                        )
                    })
                ])
            ]

        case .agents, .skills, .connectors:
            return []
        }
    }

    // MARK: - Actions

    private func refreshProfile(silent: Bool) {
        if !silent { Feedback.tap() }
        NotionAPI.shared.loadUserContent { [weak self] result in
            guard let self = self else { return }
            self.rebuild()
            guard !silent else { return }
            switch result {
            case .success:
                Feedback.success()
            case .failure(let error):
                Feedback.error()
                let alert = UIAlertController(
                    title: "Could not load account",
                    message: error.localizedDescription,
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(alert, animated: true)
            }
        }
    }

    private func presentSwitcher() {
        Feedback.tap()
        let switcher = WorkspaceSwitcherViewController()
        switcher.onSwitch = { [weak self] _ in
            self?.rebuild()
        }
        navigationController?.pushViewController(switcher, animated: true)
    }

    private func presentModelPicker() {
        Feedback.tap()
        let settings = AppSettings.shared
        let picker = ModelPickerViewController(model: settings.selectedModel, effort: settings.effort)
        picker.onChange = { [weak self] model, effort in
            settings.selectedModel = model
            settings.effort = effort
            self?.rebuild()
        }
        navigationController?.pushViewController(picker, animated: true)
    }

    private func editEndpoint() {
        Feedback.tap()
        let alert = UIAlertController(
            title: "AI endpoint path",
            message: "Path after api/v3/. The app also tries known fallbacks automatically.",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.text = AppSettings.shared.aiEndpointPath
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Reset", style: .destructive) { [weak self] _ in
            AppSettings.shared.aiEndpointPath = NotionEndpoints.defaultAIPath
            Feedback.warning()
            self?.rebuild()
        })
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            let value = (alert.textFields?.first?.text ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { AppSettings.shared.aiEndpointPath = value }
            Feedback.success()
            self?.rebuild()
        })
        present(alert, animated: true)
    }

    private func addMemory() {
        Feedback.tap()
        let alert = UIAlertController(title: "Remember this", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "I prefer short answers" }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            let text = (alert.textFields?.first?.text ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            LibraryStore.shared.addMemory(text: text, source: "Manual")
            Feedback.success()
            self?.rebuild()
        })
        present(alert, animated: true)
    }

    private func pickHour(isStart: Bool) {
        Feedback.tap()
        let sheet = UIAlertController(
            title: isStart ? "Quiet hours start" : "Quiet hours end",
            message: nil,
            preferredStyle: .actionSheet
        )
        for hour in stride(from: 0, to: 24, by: 1) {
            sheet.addAction(UIAlertAction(title: String(format: "%02d:00", hour), style: .default) { [weak self] _ in
                if isStart {
                    AppSettings.shared.quietHoursStart = hour
                } else {
                    AppSettings.shared.quietHoursEnd = hour
                }
                Feedback.selection()
                self?.rebuild()
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet.popoverPresentationController?.sourceView = view
        sheet.popoverPresentationController?.sourceRect = view.bounds
        present(sheet, animated: true)
    }

    private func confirmSignOut() {
        let alert = UIAlertController(
            title: "Sign out of Notion?",
            message: "Your local chats stay on the device.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Sign out", style: .destructive) { _ in
            Feedback.warning()
            NotionSession.shared.signOut {
                UIApplication.shared.windows.first?.rootViewController = LoginViewController()
            }
        })
        present(alert, animated: true)
    }

    private func confirmDeleteChats() {
        let alert = UIAlertController(
            title: "Delete all chats?",
            message: "This cannot be undone.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            ConversationStore.shared.deleteAll()
            Feedback.warning()
            RootController.current?.startNewChat()
        })
        present(alert, animated: true)
    }
}

extension SettingsDetailViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { blocks.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        blocks[section].rows.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        blocks[section].header
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        blocks[section].footer
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = blocks[indexPath.section].rows[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.backgroundColor = Theme.surface
        cell.textLabel?.text = row.title
        cell.textLabel?.font = .systemFont(ofSize: 16)
        cell.textLabel?.textColor = row.destructive ? Theme.destructive : Theme.textPrimary
        cell.textLabel?.numberOfLines = 0
        cell.detailTextLabel?.text = row.subtitle
        cell.detailTextLabel?.textColor = Theme.textTertiary
        cell.detailTextLabel?.font = .systemFont(ofSize: 12)
        cell.detailTextLabel?.numberOfLines = 0
        cell.tintColor = Theme.accent
        cell.accessoryView = nil
        cell.accessoryType = .none

        switch row.accessory {
        case .none:
            cell.selectionStyle = row.action == nil ? .none : .default
        case .disclosure:
            cell.accessoryType = .disclosureIndicator
        case .checkmark(let isOn):
            cell.accessoryType = isOn ? .checkmark : .none
        case .value(let text):
            let label = UILabel()
            label.text = text
            label.textColor = Theme.textSecondary
            label.font = .systemFont(ofSize: 14)
            label.sizeToFit()
            cell.accessoryView = label
        case .toggle(let isOn, let handler):
            let toggle = UISwitch()
            toggle.onTintColor = Theme.accent
            toggle.isOn = isOn
            toggle.addAction(
                UIAction { action in
                    guard let control = action.sender as? UISwitch else { return }
                    Feedback.toggle(control.isOn)
                    handler(control.isOn)
                },
                for: .valueChanged
            )
            cell.accessoryView = toggle
            cell.selectionStyle = .none
        }

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        blocks[indexPath.section].rows[indexPath.row].action?()
    }
}

// MARK: - Raw response viewer

final class RawResponseViewController: UIViewController {
    private let textView = UITextView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        title = "Last response"

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .action,
            target: self,
            action: #selector(copyPayload)
        )

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = Theme.codeBackground
        textView.textColor = Theme.textSecondary
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.isEditable = false
        textView.textContainerInset = UIEdgeInsets(top: 14, left: 12, bottom: 14, right: 12)

        let settings = AppSettings.shared
        let payload = settings.lastRawResponse
        textView.text = payload.isEmpty
            ? "No response captured yet. Send a message first."
            : settings.lastRequestInfo + "\n\n" + payload

        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12)
        ])
    }

    @objc private func copyPayload() {
        UIPasteboard.general.string = textView.text
        Feedback.success()
    }
}
