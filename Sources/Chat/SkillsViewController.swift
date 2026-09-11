import UIKit

/// Create, edit, enable and pick skills. Used both from Settings and from the
/// composer when the user types "/".
final class SkillsViewController: UIViewController {
    /// Called when a skill is picked for insertion into the composer.
    var onPick: ((Skill) -> Void)?

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var skills: [Skill] = []
    private let pickMode: Bool

    init(pickMode: Bool) {
        self.pickMode = pickMode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        title = "Skills"

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(createSkill)
        )
        if pickMode {
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .close,
                target: self,
                action: #selector(close)
            )
        }

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = Theme.background
        tableView.separatorColor = Theme.border
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 64
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
        skills = LibraryStore.shared.skills
        tableView.reloadData()
    }

    @objc private func close() {
        Feedback.tap()
        dismiss(animated: true)
    }

    @objc private func createSkill() {
        Feedback.tap()
        let editor = SkillEditorViewController(skill: nil)
        navigationController?.pushViewController(editor, animated: true)
    }
}

extension SkillsViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(skills.count, 1)
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        pickMode
            ? "Tap a skill to drop its prompt into the composer."
            : "Active skills are sent with every message. Swipe to delete your own skills."
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.backgroundColor = Theme.surface
        cell.textLabel?.textColor = Theme.textPrimary
        cell.detailTextLabel?.textColor = Theme.textTertiary
        cell.detailTextLabel?.numberOfLines = 2
        cell.textLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        cell.detailTextLabel?.font = .systemFont(ofSize: 12)

        guard !skills.isEmpty else {
            cell.textLabel?.text = "No skills yet"
            cell.detailTextLabel?.text = "Tap + to write your first one"
            cell.selectionStyle = .none
            return cell
        }

        let skill = skills[indexPath.row]
        cell.textLabel?.text = skill.icon + "  " + skill.name
        cell.detailTextLabel?.text = skill.prompt

        if pickMode {
            cell.accessoryType = .disclosureIndicator
        } else {
            let toggle = UISwitch()
            toggle.onTintColor = Theme.accent
            toggle.isOn = AppSettings.shared.isSkillActive(skill.id)
            toggle.tag = indexPath.row
            toggle.addTarget(self, action: #selector(toggleActive(_:)), for: .valueChanged)
            cell.accessoryView = toggle
        }
        return cell
    }

    @objc private func toggleActive(_ sender: UISwitch) {
        guard sender.tag < skills.count else { return }
        Feedback.toggle(sender.isOn)
        AppSettings.shared.setSkill(skills[sender.tag].id, active: sender.isOn)
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !skills.isEmpty else { return }
        let skill = skills[indexPath.row]
        Feedback.selection()

        if pickMode {
            dismiss(animated: true) { [onPick] in onPick?(skill) }
        } else {
            navigationController?.pushViewController(SkillEditorViewController(skill: skill), animated: true)
        }
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        guard !skills.isEmpty else { return false }
        return !skills[indexPath.row].builtIn
    }

    func tableView(
        _ tableView: UITableView,
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath
    ) {
        guard editingStyle == .delete, indexPath.row < skills.count else { return }
        Feedback.warning()
        LibraryStore.shared.deleteSkill(id: skills[indexPath.row].id)
    }
}

// MARK: - Editor

final class SkillEditorViewController: UIViewController {
    private let original: Skill?
    private let nameField = UITextField()
    private let iconField = UITextField()
    private let promptView = UITextView()

    init(skill: Skill?) {
        self.original = skill
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        title = original == nil ? "New skill" : "Edit skill"

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Save",
            style: .done,
            target: self,
            action: #selector(save)
        )

        let iconLabel = sectionLabel("ICON")
        let nameLabel = sectionLabel("NAME")
        let promptLabel = sectionLabel("PROMPT")

        style(field: iconField, placeholder: "✨")
        style(field: nameField, placeholder: "Weekly review")

        promptView.translatesAutoresizingMaskIntoConstraints = false
        promptView.backgroundColor = Theme.surface
        promptView.textColor = Theme.textPrimary
        promptView.font = .systemFont(ofSize: 15)
        promptView.layer.cornerRadius = Theme.cardRadius
        promptView.layer.borderWidth = 1
        promptView.layer.borderColor = Theme.border.cgColor
        promptView.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
        promptView.keyboardAppearance = .dark

        iconField.text = original?.icon ?? "✨"
        nameField.text = original?.name
        promptView.text = original?.prompt

        let stack = UIStackView(arrangedSubviews: [
            iconLabel, iconField, nameLabel, nameField, promptLabel, promptView
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 8
        stack.setCustomSpacing(18, after: iconField)
        stack.setCustomSpacing(18, after: nameField)
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            iconField.heightAnchor.constraint(equalToConstant: 46),
            nameField.heightAnchor.constraint(equalToConstant: 46),
            promptView.heightAnchor.constraint(equalToConstant: 190)
        ])
    }

    private func sectionLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = Theme.textTertiary
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        return label
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
        let padding = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        field.leftView = padding
        field.leftViewMode = .always
    }

    @objc private func save() {
        let name = (nameField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = (promptView.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !prompt.isEmpty else {
            Feedback.error()
            let alert = UIAlertController(
                title: "Missing details",
                message: "A skill needs a name and a prompt.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }

        var skill = original ?? Skill(name: name, icon: "✨", prompt: prompt)
        skill.name = name
        skill.prompt = prompt
        let icon = (iconField.text ?? "").trimmingCharacters(in: .whitespaces)
        skill.icon = icon.isEmpty ? "✨" : String(icon.prefix(2))
        LibraryStore.shared.upsert(skill: skill)
        Feedback.success()
        navigationController?.popViewController(animated: true)
    }
}
