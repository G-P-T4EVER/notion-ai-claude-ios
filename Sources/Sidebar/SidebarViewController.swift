import UIKit

protocol SidebarDelegate: AnyObject {
    func sidebarDidRequestNewChat()
    func sidebarDidSelect(conversationID: String)
    func sidebarDidRequestSettings()
    func sidebarDidRequestWorkspace()
}

/// Slide-over drawer: search, recent chats, workspace shortcut, account row.
final class SidebarViewController: UIViewController {
    weak var delegate: SidebarDelegate?

    private let searchBar = UISearchBar()
    private let newChatButton = UIButton(type: .system)
    private let table = UITableView(frame: .zero, style: .plain)
    private let accountButton = UIButton(type: .system)

    private var rows: [Conversation] = []
    private var query = ""

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.surface

        newChatButton.setTitle("  New chat", for: .normal)
        newChatButton.setImage(UIImage(systemName: "plus"), for: .normal)
        newChatButton.tintColor = Theme.textPrimary
        newChatButton.setTitleColor(Theme.textPrimary, for: .normal)
        newChatButton.titleLabel?.font = AppSettings.shared.chatFont.font(size: 16, weight: .medium)
        newChatButton.contentHorizontalAlignment = .leading
        newChatButton.translatesAutoresizingMaskIntoConstraints = false
        newChatButton.addTarget(self, action: #selector(newChatTapped), for: .touchUpInside)
        view.addSubview(newChatButton)

        searchBar.placeholder = "Search your chats"
        searchBar.searchBarStyle = .minimal
        searchBar.barStyle = .black
        searchBar.tintColor = Theme.accent
        searchBar.delegate = self
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchBar)

        table.backgroundColor = Theme.surface
        table.separatorStyle = .none
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 52
        table.register(UITableViewCell.self, forCellReuseIdentifier: "SidebarRow")
        table.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(table)

        accountButton.contentHorizontalAlignment = .leading
        accountButton.titleLabel?.font = AppSettings.shared.chatFont.font(size: 14)
        accountButton.setTitleColor(Theme.textSecondary, for: .normal)
        accountButton.setImage(UIImage(systemName: "person.crop.circle"), for: .normal)
        accountButton.tintColor = Theme.textSecondary
        accountButton.translatesAutoresizingMaskIntoConstraints = false
        accountButton.addTarget(self, action: #selector(accountTapped), for: .touchUpInside)
        view.addSubview(accountButton)

        NSLayoutConstraint.activate([
            newChatButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            newChatButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            newChatButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            newChatButton.heightAnchor.constraint(equalToConstant: 40),

            searchBar.topAnchor.constraint(equalTo: newChatButton.bottomAnchor, constant: 4),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),

            table.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 4),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: accountButton.topAnchor, constant: -8),

            accountButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            accountButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            accountButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            accountButton.heightAnchor.constraint(equalToConstant: 44)
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reload),
            name: ConversationStore.didChangeNotification,
            object: nil
        )

        reload()
    }

    @objc func reload() {
        rows = ConversationStore.shared.search(query).filter { !$0.messages.isEmpty }
        table.reloadData()

        let name = NotionSession.shared.userName ?? NotionSession.shared.userEmail ?? "Account"
        let space = NotionSession.shared.spaceName
        accountButton.setTitle("  " + name + (space == nil ? "" : "  \u{00B7}  " + space!), for: .normal)
    }

    @objc private func newChatTapped() {
        Haptics.tap()
        delegate?.sidebarDidRequestNewChat()
    }

    @objc private func accountTapped() {
        Haptics.tap()
        delegate?.sidebarDidRequestSettings()
    }
}

extension SidebarViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        query = searchText
        reload()
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

extension SidebarViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { 2 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 1 : rows.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 1 && !rows.isEmpty ? "Recents" : nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SidebarRow", for: indexPath)
        cell.backgroundColor = Theme.surface
        cell.textLabel?.textColor = Theme.textPrimary
        cell.textLabel?.font = AppSettings.shared.chatFont.font(size: 15)
        cell.textLabel?.numberOfLines = 1
        cell.selectedBackgroundView = {
            let view = UIView()
            view.backgroundColor = Theme.surfaceRaised
            return view
        }()

        if indexPath.section == 0 {
            cell.textLabel?.text = "Browse workspace"
            cell.imageView?.image = UIImage(systemName: "square.grid.2x2")
            cell.imageView?.tintColor = Theme.textSecondary
        } else {
            cell.textLabel?.text = rows[indexPath.row].title
            cell.imageView?.image = UIImage(systemName: "bubble.left")
            cell.imageView?.tintColor = Theme.textTertiary
        }

        return cell
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard section == 1, !rows.isEmpty else { return nil }

        let container = UIView()
        container.backgroundColor = Theme.surface

        let label = UILabel()
        label.text = "Recents"
        label.textColor = Theme.textTertiary
        label.font = AppSettings.shared.chatFont.font(size: 12, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6)
        ])
        return container
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        section == 1 && !rows.isEmpty ? 30 : 0
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if indexPath.section == 0 {
            delegate?.sidebarDidRequestWorkspace()
        } else {
            delegate?.sidebarDidSelect(conversationID: rows[indexPath.row].id)
        }
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard indexPath.section == 1 else { return nil }
        let conversation = rows[indexPath.row]

        let delete = UIContextualAction(style: .destructive, title: "Delete") { _, _, done in
            ConversationStore.shared.delete(id: conversation.id)
            self.reload()
            done(true)
        }

        let rename = UIContextualAction(style: .normal, title: "Rename") { [weak self] _, _, done in
            guard let self = self else { return }

            let alert = UIAlertController(title: "Rename chat", message: nil, preferredStyle: .alert)
            alert.addTextField { field in
                field.text = conversation.title
            }
            alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in
                var updated = conversation
                updated.title = alert.textFields?.first?.text ?? conversation.title
                ConversationStore.shared.save(updated)
                self.reload()
            })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
            self.present(alert, animated: true, completion: nil)
            done(true)
        }
        rename.backgroundColor = Theme.surfaceRaised

        return UISwipeActionsConfiguration(actions: [delete, rename])
    }
}
