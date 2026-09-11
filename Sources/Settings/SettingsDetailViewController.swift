import UIKit
import SafariServices

/// One detail pane per settings section.
final class SettingsDetailViewController: UIViewController {
    private let section: SettingsSection
    private let table = UITableView(frame: .zero, style: .grouped)
    private var blocks: [SettingsBlock] = []

    init(section: SettingsSection) {
        self.section = section
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = section.title
        view.backgroundColor = Theme.background

        table.backgroundColor = Theme.background
        table.separatorColor = Theme.border
        table.dataSource = self
        table.delegate = self
        table.estimatedRowHeight = 54
        table.rowHeight = UITableView.automaticDimension
        table.register(UITableViewCell.self, forCellReuseIdentifier: "DetailRow")
        view.addSubview(table)
        table.pinEdges(to: view)

        if section == .reflect {
            let header = ReflectHeaderView(
                frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 330)
            )
            header.reload()
            table.tableHeaderView = header
        }

        rebuild()
    }

    private func rebuild() {
        blocks = makeBlocks()
        table.reloadData()
    }

    // MARK: - Content

    private func makeBlocks() -> [SettingsBlock] {
        let settings = AppSettings.shared

        switch section {
        case .general:
            let fontRows = ChatFontChoice.allCases.map { choice in
                SettingsRow(
                    title: choice.title,
                    accessory: .checkmark(settings.chatFont == choice),
                    action: { [weak self] in
                        AppSettings.shared.chatFont = choice
                        self?.rebuild()
                    }
                )
            }

            return [
                SettingsBlock(header: "Chat font", footer: nil, rows: fontRows),
                SettingsBlock(
                    header: "Motion",
                    footer: "Reduce animation in streaming responses and other interface elements.",
                    rows: [
                        SettingsRow(
                            title: "Reduce animation",
                            accessory: .toggle(settings.reduceMotion) { value in
                                AppSettings.shared.reduceMotion = value
                            }
                        )
                    ]
                ),
                SettingsBlock(header: "Composer", footer: nil, rows: [
                    SettingsRow(
                        title: "Send with Return",
                        accessory: .toggle(settings.sendOnReturn) { value in
                            AppSettings.shared.sendOnReturn = value
                        }
                    ),
                    SettingsRow(
                        title: "Haptics",
                        accessory: .toggle(settings.hapticsEnabled) { value in
                            AppSettings.shared.hapticsEnabled = value
                        }
                    ),
                    SettingsRow(
                        title: "Default mode",
                        accessory: .value(settings.mode.title),
                        action: { [weak self] in
                            AppSettings.shared.mode = settings.mode == .chat ? .cowork : .chat
                            self?.rebuild()
                        }
                    )
                ])
            ]

        case .account:
            let session = NotionSession.shared
            return [
                SettingsBlock(header: "Signed in", footer: nil, rows: [
                    SettingsRow(title: "Name", accessory: .value(session.userName ?? "Unknown")),
                    SettingsRow(title: "Email", accessory: .value(session.userEmail ?? "Unknown")),
                    SettingsRow(title: "Workspace", accessory: .value(session.spaceName ?? "Unknown"))
                ]),
                SettingsBlock(header: nil, footer: nil, rows: [
                    SettingsRow(
                        title: "Open account settings on notion.so",
                        accessory: .disclosure,
                        action: { [weak self] in self?.openWeb("/my-settings") }
                    ),
                    SettingsRow(
                        title: "Sign out",
                        destructive: true,
                        action: { [weak self] in self?.confirmSignOut() }
                    )
                ])
            ]

        case .privacy:
            return [
                SettingsBlock(
                    header: "Usage",
                    footer: "This client never sends data anywhere except Notion's own servers.",
                    rows: [
                        SettingsRow(
                            title: "Opt out of usage analytics",
                            accessory: .toggle(settings.analyticsOptOut) { value in
                                AppSettings.shared.analyticsOptOut = value
                            }
                        )
                    ]
                ),
                SettingsBlock(header: "Local data", footer: "Chat history is stored only on this device.", rows: [
                    SettingsRow(
                        title: "Delete all chats",
                        destructive: true,
                        action: { [weak self] in self?.confirmDeleteChats() }
                    )
                ])
            ]

        case .billing:
            return [
                SettingsBlock(header: nil, footer: "Plans and invoices are managed by Notion.", rows: [
                    SettingsRow(
                        title: "Manage plan",
                        accessory: .disclosure,
                        action: { [weak self] in self?.openWeb("/settings/billing") }
                    )
                ])
            ]

        case .capabilities:
            let modelRows = AIModel.all.map { model in
                SettingsRow(
                    title: model.name,
                    subtitle: model.effort,
                    accessory: .checkmark(settings.selectedModel == model),
                    action: { [weak self] in
                        AppSettings.shared.selectedModel = model
                        self?.rebuild()
                    }
                )
            }

            return [
                SettingsBlock(header: "Model", footer: nil, rows: modelRows),
                SettingsBlock(
                    header: "Advanced",
                    footer: "Notion's AI endpoint is not public. If a server change breaks replies, set the new path here instead of waiting for a new build.",
                    rows: [
                        SettingsRow(
                            title: "AI endpoint path",
                            accessory: .value(settings.aiEndpointPath),
                            action: { [weak self] in self?.editEndpoint() }
                        )
                    ]
                )
            ]

        case .memory:
            return [
                SettingsBlock(
                    header: nil,
                    footer: "When on, recent chats from this device are used as context for new answers.",
                    rows: [
                        SettingsRow(
                            title: "Use chat memory",
                            accessory: .toggle(settings.memoryEnabled) { value in
                                AppSettings.shared.memoryEnabled = value
                            }
                        )
                    ]
                )
            ]

        case .reflect:
            return [
                SettingsBlock(header: nil, footer: "Computed on device from your local chat history.", rows: [
                    SettingsRow(
                        title: "Decide when Notion AI is off",
                        accessory: .disclosure,
                        action: { [weak self] in
                            guard let self = self else { return }
                            self.navigationController?.pushViewController(
                                SettingsDetailViewController(section: .timeAndFocus),
                                animated: true
                            )
                        }
                    )
                ])
            ]

        case .timeAndFocus:
            return [
                SettingsBlock(
                    header: "Quiet hours",
                    footer: "During quiet hours the app stops nudging you and starts in read-only mode.",
                    rows: [
                        SettingsRow(
                            title: "Enable quiet hours",
                            accessory: .toggle(settings.quietHoursEnabled) { [weak self] value in
                                AppSettings.shared.quietHoursEnabled = value
                                self?.rebuild()
                            }
                        ),
                        SettingsRow(
                            title: "Starts at",
                            accessory: .value(SettingsDetailViewController.hourLabel(settings.quietHoursStart)),
                            action: { [weak self] in self?.editHour(isStart: true) }
                        ),
                        SettingsRow(
                            title: "Ends at",
                            accessory: .value(SettingsDetailViewController.hourLabel(settings.quietHoursEnd)),
                            action: { [weak self] in self?.editHour(isStart: false) }
                        ),
                        SettingsRow(
                            title: "Right now",
                            accessory: .value(settings.isQuietTimeNow ? "Quiet" : "Active")
                        )
                    ]
                )
            ]

        case .claudeCode:
            return [
                SettingsBlock(
                    header: nil,
                    footer: "Claude Code is a desktop and terminal feature. This screen exists so the settings tree matches the desktop client.",
                    rows: [
                        SettingsRow(title: "Status", accessory: .value("Not available on iOS"))
                    ]
                )
            ]

        case .skills:
            let skills: [(String, String)] = [
                ("Summarize a page", "Summarize this Notion page in five bullets: "),
                ("Draft a doc", "Draft a Notion doc about "),
                ("Rewrite", "Rewrite the following text to be clearer: "),
                ("Translate", "Translate the following into Russian: "),
                ("Action items", "Pull the action items out of this: "),
                ("Meeting recap", "Write a recap of this meeting: ")
            ]

            return [
                SettingsBlock(
                    header: "Skills",
                    footer: "Type / in the composer to reach these quickly.",
                    rows: skills.map { skill in
                        SettingsRow(
                            title: skill.0,
                            accessory: .disclosure,
                            action: {
                                RootController.current?.prefillComposer(with: skill.1)
                            }
                        )
                    }
                )
            ]

        case .connectors:
            return [
                SettingsBlock(
                    header: nil,
                    footer: "Connectors are configured in your Notion workspace and apply automatically here.",
                    rows: [
                        SettingsRow(
                            title: "Manage connections",
                            accessory: .disclosure,
                            action: { [weak self] in self?.openWeb("/settings/connections") }
                        )
                    ]
                )
            ]

        case .plugins:
            return [
                SettingsBlock(
                    header: nil,
                    footer: "Plugin support ships with the desktop client only.",
                    rows: [
                        SettingsRow(title: "Installed plugins", accessory: .value("0"))
                    ]
                )
            ]
        }
    }

    // MARK: - Helpers

    private static func hourLabel(_ hour: Int) -> String {
        let clamped = max(0, min(23, hour))
        return String(format: "%02d:00", clamped)
    }

    private func openWeb(_ path: String) {
        guard let url = URL(string: NotionEndpoints.host + path) else { return }
        present(SFSafariViewController(url: url), animated: true, completion: nil)
    }

    private func editEndpoint() {
        let alert = UIAlertController(
            title: "AI endpoint path",
            message: "Path under /api/v3/",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.text = AppSettings.shared.aiEndpointPath
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            AppSettings.shared.aiEndpointPath = alert.textFields?.first?.text ?? ""
            self?.rebuild()
        })
        alert.addAction(UIAlertAction(title: "Reset", style: .destructive) { [weak self] _ in
            AppSettings.shared.aiEndpointPath = NotionEndpoints.defaultAIPath
            self?.rebuild()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(alert, animated: true, completion: nil)
    }

    private func editHour(isStart: Bool) {
        let alert = UIAlertController(
            title: isStart ? "Quiet hours start" : "Quiet hours end",
            message: "Hour of the day, 0 to 23",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.keyboardType = .numberPad
            field.text = String(isStart ? AppSettings.shared.quietHoursStart : AppSettings.shared.quietHoursEnd)
        }
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            let value = Int(alert.textFields?.first?.text ?? "") ?? 0
            let clamped = max(0, min(23, value))
            if isStart {
                AppSettings.shared.quietHoursStart = clamped
            } else {
                AppSettings.shared.quietHoursEnd = clamped
            }
            self?.rebuild()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(alert, animated: true, completion: nil)
    }

    private func confirmSignOut() {
        let alert = UIAlertController(
            title: "Sign out?",
            message: "Your Notion session will be removed from this device.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Sign out", style: .destructive) { [weak self] _ in
            NotionSession.shared.signOut()
            self?.dismiss(animated: true, completion: nil)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(alert, animated: true, completion: nil)
    }

    private func confirmDeleteChats() {
        let alert = UIAlertController(
            title: "Delete all chats?",
            message: "This cannot be undone.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            ConversationStore.shared.deleteAll()
            Haptics.success()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(alert, animated: true, completion: nil)
    }

    @objc private func toggleChanged(_ sender: UISwitch) {
        let indexPath = IndexPath(row: sender.tag % 1000, section: sender.tag / 1000)
        guard indexPath.section < blocks.count,
              indexPath.row < blocks[indexPath.section].rows.count else { return }

        if case .toggle(_, let handler) = blocks[indexPath.section].rows[indexPath.row].accessory {
            handler(sender.isOn)
            blocks = makeBlocks()
        }
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
        let cell = UITableViewCell(style: .value1, reuseIdentifier: "DetailRow")

        cell.backgroundColor = Theme.surface
        cell.textLabel?.text = row.title
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.font = AppSettings.shared.chatFont.font(size: 16)
        cell.textLabel?.textColor = row.destructive ? Theme.destructive : Theme.textPrimary
        cell.detailTextLabel?.textColor = Theme.textSecondary
        cell.detailTextLabel?.font = AppSettings.shared.chatFont.font(size: 14)
        cell.detailTextLabel?.text = row.subtitle
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.selectionStyle = row.action == nil ? .none : .default

        switch row.accessory {
        case .none:
            break

        case .checkmark(let isOn):
            cell.accessoryType = isOn ? .checkmark : .none

        case .disclosure:
            cell.accessoryType = .disclosureIndicator

        case .value(let value):
            cell.detailTextLabel?.text = value

        case .toggle(let isOn, _):
            let toggle = UISwitch()
            toggle.isOn = isOn
            toggle.onTintColor = Theme.accent
            toggle.tag = indexPath.section * 1000 + indexPath.row
            toggle.addTarget(self, action: #selector(toggleChanged(_:)), for: .valueChanged)
            cell.accessoryView = toggle
        }

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        blocks[indexPath.section].rows[indexPath.row].action?()
    }
}
