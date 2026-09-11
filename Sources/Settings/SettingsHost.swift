import UIKit

/// Builds the settings stack. The desktop client shows a two-pane modal; on
/// phones the same information is a list that pushes detail screens.
enum SettingsHost {
    static func makeViewController(initialSection: SettingsSection = .general) -> UIViewController {
        let list = SettingsListViewController()
        let navigation = UINavigationController(rootViewController: list)

        navigation.navigationBar.barTintColor = Theme.surface
        navigation.navigationBar.tintColor = Theme.accent
        navigation.navigationBar.titleTextAttributes = [.foregroundColor: Theme.textPrimary]
        navigation.navigationBar.isTranslucent = false
        navigation.view.backgroundColor = Theme.background

        if initialSection != .general {
            navigation.pushViewController(
                SettingsDetailViewController(section: initialSection),
                animated: false
            )
        }

        return navigation
    }
}

final class SettingsListViewController: UIViewController {
    private let table = UITableView(frame: .zero, style: .grouped)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        view.backgroundColor = Theme.background

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(close)
        )

        table.backgroundColor = Theme.background
        table.separatorColor = Theme.border
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 50
        table.register(UITableViewCell.self, forCellReuseIdentifier: "SectionRow")
        table.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(table)
        table.pinEdges(to: view)
    }

    @objc private func close() {
        dismiss(animated: true, completion: nil)
    }
}

extension SettingsListViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        SettingsGroup.allCases.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        SettingsGroup.allCases[section].title
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        SettingsSection.sections(in: SettingsGroup.allCases[section]).count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SectionRow", for: indexPath)
        let section = SettingsSection.sections(in: SettingsGroup.allCases[indexPath.section])[indexPath.row]

        cell.backgroundColor = Theme.surface
        cell.textLabel?.text = section.title
        cell.textLabel?.textColor = Theme.textPrimary
        cell.textLabel?.font = AppSettings.shared.chatFont.font(size: 16)
        cell.imageView?.image = UIImage(systemName: section.symbol)
        cell.imageView?.tintColor = Theme.textSecondary
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let section = SettingsSection.sections(in: SettingsGroup.allCases[indexPath.section])[indexPath.row]
        navigationController?.pushViewController(
            SettingsDetailViewController(section: section),
            animated: !AppSettings.shared.motionReduced
        )
    }
}
