import UIKit

/// Agent list with creation, editing, personalisation and a default agent.
final class AgentsViewController: UIViewController {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var agents: [AgentProfile] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        title = "Agents"

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(createAgent)
        )

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = Theme.background
        tableView.separatorColor = Theme.border
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 66
        view.addSubview(tableView)
        tableView.pinEdges(to: view)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reload),
            name: LibraryStore.didChangeNotification,
            object: nil
        )
        reload()
    }

    @objc private func reload() {
        agents = LibraryStore.shared.agents
        tableView.reloadData()
    }

    @objc private func createAgent() {
        Feedback.tap()
        navigationController?.pushViewController(AgentEditorViewController(agent: nil), animated: true)
    }
}

extension AgentsViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { 2 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? max(agents.count, 1) : 1
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "YOUR AGENTS" : "DEFAULT"
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 1
            ? "The default agent's instructions, model and effort are applied to every new chat."
            : nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.backgroundColor = Theme.surface
        cell.textLabel?.textColor = Theme.textPrimary
        cell.textLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        cell.detailTextLabel?.textColor = Theme.textTertiary
        cell.detailTextLabel?.font = .systemFont(ofSize: 12)
        cell.detailTextLabel?.numberOfLines = 2
        cell.tintColor = Theme.accent

        if indexPath.section == 1 {
            let current = AppSettings.shared.defaultAgentID
                .flatMap { LibraryStore.shared.agent(withID: $0) }
            cell.textLabel?.text = "Default agent"
            cell.detailTextLabel?.text = current?.name ?? "None — plain Notion AI"
            cell.accessoryType = .disclosureIndicator
            return cell
        }

        guard !agents.isEmpty else {
            cell.textLabel?.text = "No agents yet"
            cell.detailTextLabel?.text = "Tap + to create one"
            cell.selectionStyle = .none
            return cell
        }

        let agent = agents[indexPath.row]
        cell.textLabel?.text = agent.icon + "  " + agent.name
        cell.detailTextLabel?.text = agent.model.name + " · " + agent.effort.title
            + " · " + agent.tone
        cell.accessoryType = .disclosureIndicator
        if AppSettings.shared.defaultAgentID == agent.id {
            cell.textLabel?.textColor = Theme.accent
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        Feedback.selection()

        if indexPath.section == 1 {
            let sheet = UIAlertController(title: "Default agent", message: nil, preferredStyle: .actionSheet)
            sheet.addAction(UIAlertAction(title: "None", style: .default) { _ in
                AppSettings.shared.defaultAgentID = nil
                Feedback.success()
                self.tableView.reloadData()
            })
            for agent in agents {
                sheet.addAction(UIAlertAction(title: agent.name, style: .default) { _ in
                    AppSettings.shared.defaultAgentID = agent.id
                    Feedback.success()
                    self.tableView.reloadData()
                })
            }
            sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            sheet.popoverPresentationController?.sourceView = view
            sheet.popoverPresentationController?.sourceRect = view.bounds
            present(sheet, animated: true)
            return
        }

        guard !agents.isEmpty else { return }
        navigationController?.pushViewController(
            AgentEditorViewController(agent: agents[indexPath.row]),
            animated: true
        )
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        indexPath.section == 0 && !agents.isEmpty
    }

    func tableView(
        _ tableView: UITableView,
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath
    ) {
        guard editingStyle == .delete, indexPath.row < agents.count else { return }
        Feedback.warning()
        LibraryStore.shared.deleteAgent(id: agents[indexPath.row].id)
    }
}

// MARK: - Editor

final class AgentEditorViewController: UIViewController {
    private var draft: AgentProfile
    private let isNew: Bool

    private let scrollView = UIScrollView()
    private let iconField = UITextField()
    private let nameField = UITextField()
    private let instructionsView = UITextView()
    private let toneControl = UISegmentedControl(items: ["Neutral", "Direct", "Warm", "Analytical"])
    private let modelRow = UIButton(type: .system)
    private let skillsRow = UIButton(type: .system)

    init(agent: AgentProfile?) {
        self.draft = agent ?? AgentProfile(
            name: "",
            icon: "🤖",
            instructions: "",
            modelID: AppSettings.shared.selectedModel.id,
            effortRaw: AppSettings.shared.effort.rawValue
        )
        self.isNew = agent == nil
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        title = isNew ? "New agent" : draft.name

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Save",
            style: .done,
            target: self,
            action: #selector(save)
        )

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        style(field: iconField, placeholder: "🤖")
        style(field: nameField, placeholder: "Research buddy")
        iconField.text = draft.icon
        nameField.text = draft.name

        instructionsView.translatesAutoresizingMaskIntoConstraints = false
        instructionsView.backgroundColor = Theme.surface
        instructionsView.textColor = Theme.textPrimary
        instructionsView.font = .systemFont(ofSize: 15)
        instructionsView.layer.cornerRadius = Theme.cardRadius
        instructionsView.layer.borderWidth = 1
        instructionsView.layer.borderColor = Theme.border.cgColor
        instructionsView.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
        instructionsView.keyboardAppearance = .dark
        instructionsView.text = draft.instructions

        toneControl.translatesAutoresizingMaskIntoConstraints = false
        toneControl.selectedSegmentTintColor = Theme.accent
        toneControl.backgroundColor = Theme.surface
        toneControl.setTitleTextAttributes([.foregroundColor: Theme.textSecondary], for: .normal)
        toneControl.setTitleTextAttributes([.foregroundColor: UIColor(hex: 0x1A1A19)], for: .selected)
        toneControl.selectedSegmentIndex = ["Neutral", "Direct", "Warm", "Analytical"]
            .firstIndex(of: draft.tone) ?? 0
        toneControl.addTarget(self, action: #selector(toneChanged), for: .valueChanged)

        configureRow(modelRow, action: #selector(pickModel))
        configureRow(skillsRow, action: #selector(pickSkills))
        refreshRows()

        let stack = UIStackView(arrangedSubviews: [
            label("ICON"), iconField,
            label("NAME"), nameField,
            label("INSTRUCTIONS"), instructionsView,
            label("TONE"), toneControl,
            label("MODEL"), modelRow,
            label("SKILLS"), skillsRow
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 8
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -40),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),

            iconField.heightAnchor.constraint(equalToConstant: 46),
            nameField.heightAnchor.constraint(equalToConstant: 46),
            instructionsView.heightAnchor.constraint(equalToConstant: 180),
            toneControl.heightAnchor.constraint(equalToConstant: 36),
            modelRow.heightAnchor.constraint(equalToConstant: 46),
            skillsRow.heightAnchor.constraint(equalToConstant: 46)
        ])
    }

    private func label(_ text: String) -> UILabel {
        let view = UILabel()
        view.text = text
        view.textColor = Theme.textTertiary
        view.font = .systemFont(ofSize: 11, weight: .semibold)
        return view
    }

    private func style(field: UITextField, placeholder: String) {
        field.translatesAutoresizingMaskIntoConstraints = false
        field.backgroundColor = Theme.surface
        field.textColor = Theme.textPrimary
        field.tintColor = Theme.accent
        field.font = .systemFont(ofSize: 16)
        field.layer.cornerRadius = Theme.cardRadius
        field.layer.borderWidth = 1
        field.layer.borderColor = Theme.border.cgColor
        field.keyboardAppearance = .dark
        field.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: Theme.textTertiary]
        )
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        field.leftViewMode = .always
    }

    private func configureRow(_ button: UIButton, action: Selector) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = Theme.surface
        button.layer.cornerRadius = Theme.cardRadius
        button.layer.borderWidth = 1
        button.layer.borderColor = Theme.border.cgColor
        button.contentHorizontalAlignment = .left
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
        button.setTitleColor(Theme.textPrimary, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 15)
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func refreshRows() {
        modelRow.setTitle(draft.model.name + "  ·  " + draft.effort.title, for: .normal)
        modelRow.setImage(ProviderMark.image(for: draft.model.provider, size: 16), for: .normal)
        modelRow.imageEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 8)

        let names = draft.skillIDs
            .compactMap { LibraryStore.shared.skill(withID: $0)?.name }
        skillsRow.setTitle(names.isEmpty ? "No skills attached" : names.joined(separator: ", "), for: .normal)
    }

    @objc private func toneChanged() {
        Feedback.selection()
        draft.tone = ["Neutral", "Direct", "Warm", "Analytical"][toneControl.selectedSegmentIndex]
    }

    @objc private func pickModel() {
        Feedback.tap()
        let picker = ModelPickerViewController(model: draft.model, effort: draft.effort)
        picker.onChange = { [weak self] model, effort in
            guard let self = self else { return }
            self.draft.modelID = model.id
            self.draft.effort = effort
            self.refreshRows()
        }
        present(UINavigationController(rootViewController: picker), animated: true)
    }

    @objc private func pickSkills() {
        Feedback.tap()
        let sheet = UIAlertController(title: "Attach skills", message: nil, preferredStyle: .actionSheet)
        for skill in LibraryStore.shared.skills {
            let attached = draft.skillIDs.contains(skill.id)
            let title = (attached ? "✓ " : "") + skill.name
            sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                guard let self = self else { return }
                if attached {
                    self.draft.skillIDs.removeAll { $0 == skill.id }
                } else {
                    self.draft.skillIDs.append(skill.id)
                }
                Feedback.selection()
                self.refreshRows()
            })
        }
        sheet.addAction(UIAlertAction(title: "Done", style: .cancel))
        sheet.popoverPresentationController?.sourceView = skillsRow
        sheet.popoverPresentationController?.sourceRect = skillsRow.bounds
        present(sheet, animated: true)
    }

    @objc private func save() {
        let name = (nameField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let instructions = (instructionsView.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !instructions.isEmpty else {
            Feedback.error()
            let alert = UIAlertController(
                title: "Missing details",
                message: "An agent needs a name and instructions.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }

        draft.name = name
        draft.instructions = instructions
        let icon = (iconField.text ?? "").trimmingCharacters(in: .whitespaces)
        draft.icon = icon.isEmpty ? "🤖" : String(icon.prefix(2))

        LibraryStore.shared.upsert(agent: draft)
        Feedback.success()
        navigationController?.popViewController(animated: true)
    }
}
