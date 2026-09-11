import UIKit

/// Lists every workspace the account can open and switches the active one,
/// the same way the workspace button works in Notion.
final class WorkspaceSwitcherViewController: UIViewController {
    var onSwitch: ((NotionSpace) -> Void)?

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let statusLabel = UILabel()
    private var spaces: [NotionSpace] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        title = "Workspaces"

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(close)
        )

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = Theme.background
        tableView.separatorColor = Theme.border
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 56
        view.addSubview(tableView)
        tableView.pinEdges(to: view)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textColor = Theme.textTertiary
        statusLabel.font = .systemFont(ofSize: 14)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.isHidden = true

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.color = Theme.textTertiary

        view.addSubview(statusLabel)
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
        ])

        load()
    }

    @objc private func close() {
        Feedback.tap()
        dismiss(animated: true)
    }

    private func load() {
        spinner.startAnimating()
        statusLabel.isHidden = true
        NotionAPI.shared.loadSpaces { [weak self] result in
            guard let self = self else { return }
            self.spinner.stopAnimating()
            switch result {
            case .success(let spaces):
                self.spaces = spaces
                self.tableView.reloadData()
                if spaces.isEmpty {
                    self.statusLabel.text = "No workspaces found for this account."
                    self.statusLabel.isHidden = false
                }
            case .failure(let error):
                self.statusLabel.text = error.localizedDescription
                self.statusLabel.isHidden = false
                Feedback.error()
            }
        }
    }
}

extension WorkspaceSwitcherViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        spaces.count
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        let email = NotionSession.shared.userEmail ?? ""
        return email.isEmpty ? nil : "Signed in as \(email)"
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        let space = spaces[indexPath.row]
        cell.backgroundColor = Theme.surface
        cell.textLabel?.text = space.name
        cell.textLabel?.textColor = Theme.textPrimary
        cell.textLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        cell.detailTextLabel?.text = space.id == NotionSession.shared.spaceID ? "Current workspace" : nil
        cell.detailTextLabel?.textColor = Theme.textTertiary
        cell.detailTextLabel?.font = .systemFont(ofSize: 12)
        cell.accessoryType = space.id == NotionSession.shared.spaceID ? .checkmark : .none
        cell.tintColor = Theme.accent

        let badge = UILabel()
        badge.frame = CGRect(x: 0, y: 0, width: 34, height: 34)
        badge.textAlignment = .center
        badge.backgroundColor = Theme.surfaceRaised
        badge.layer.cornerRadius = 8
        badge.clipsToBounds = true
        if let icon = space.icon, !icon.isEmpty, !icon.hasPrefix("http") {
            badge.text = icon
            badge.font = .systemFont(ofSize: 17)
        } else {
            badge.text = String(space.name.prefix(1)).uppercased()
            badge.textColor = Theme.textSecondary
            badge.font = .systemFont(ofSize: 15, weight: .semibold)
        }
        cell.imageView?.image = badge.asImage()
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let space = spaces[indexPath.row]
        guard space.id != NotionSession.shared.spaceID else {
            Feedback.tap()
            dismiss(animated: true)
            return
        }
        Feedback.success()
        NotionAPI.shared.switchSpace(to: space)
        let handler = onSwitch
        dismiss(animated: true) { handler?(space) }
    }
}

extension UIView {
    func asImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        return renderer.image { context in
            layer.render(in: context.cgContext)
        }
    }
}
