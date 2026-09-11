import UIKit
import MobileCoreServices

/// Integrations with other services plus memory import from other assistants.
final class ConnectorsViewController: UIViewController {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let categories = Connector.categories()
    private var pendingImportSource: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        title = "Connectors"

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = Theme.background
        tableView.separatorColor = Theme.border
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        view.addSubview(tableView)
        tableView.pinEdges(to: view)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reload),
            name: LibraryStore.didChangeNotification,
            object: nil
        )
    }

    @objc private func reload() {
        tableView.reloadData()
    }

    private func connectors(in category: String) -> [Connector] {
        Connector.all.filter { $0.category == category }
    }

    private func startImport(source: String) {
        pendingImportSource = source
        let types = ["public.json", "public.plain-text", "public.text", "public.data"]
        let picker = UIDocumentPickerViewController(documentTypes: types, in: .import)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    private func showImportResult(_ message: String, success: Bool) {
        success ? Feedback.success() : Feedback.error()
        let alert = UIAlertController(
            title: success ? "Memory imported" : "Import failed",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

extension ConnectorsViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        categories.count + 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 { return 4 }
        return connectors(in: categories[section - 1]).count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "IMPORT MEMORY" : categories[section - 1].uppercased()
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard section == 0 else { return nil }
        let count = LibraryStore.shared.memories.count
        let sources = LibraryStore.shared.memorySources()
            .map { "\($0.source) (\($0.count))" }
            .joined(separator: ", ")
        if count == 0 {
            return "Export your data from ChatGPT, Claude, Gemini or Grok and pick the file here. Facts are stored locally and sent with your requests."
        }
        return "\(count) memories stored locally — \(sources)"
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.backgroundColor = Theme.surface
        cell.textLabel?.textColor = Theme.textPrimary
        cell.textLabel?.font = .systemFont(ofSize: 16)
        cell.detailTextLabel?.textColor = Theme.textTertiary
        cell.detailTextLabel?.font = .systemFont(ofSize: 12)
        cell.detailTextLabel?.numberOfLines = 2
        cell.tintColor = Theme.accent

        if indexPath.section == 0 {
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "Import from ChatGPT"
                cell.detailTextLabel?.text = "conversations.json or memory export"
            case 1:
                cell.textLabel?.text = "Import from Claude"
                cell.detailTextLabel?.text = "projects or conversations export"
            case 2:
                cell.textLabel?.text = "Import from Gemini or Grok"
                cell.detailTextLabel?.text = "JSON, Markdown or plain text"
            default:
                cell.textLabel?.text = "Clear imported memory"
                cell.textLabel?.textColor = Theme.destructive
                cell.detailTextLabel?.text = nil
            }
            cell.imageView?.image = UIImage(systemName: indexPath.row == 3 ? "trash" : "square.and.arrow.down")
            cell.imageView?.tintColor = indexPath.row == 3 ? Theme.destructive : Theme.textSecondary
            return cell
        }

        let connector = connectors(in: categories[indexPath.section - 1])[indexPath.row]
        cell.textLabel?.text = connector.name
        cell.detailTextLabel?.text = connector.detail
        cell.imageView?.image = UIImage(systemName: connector.symbol)
        cell.imageView?.tintColor = Theme.textSecondary

        let toggle = UISwitch()
        toggle.onTintColor = Theme.accent
        toggle.isOn = AppSettings.shared.isConnectorEnabled(connector.id)
        toggle.accessibilityHint = connector.id
        toggle.addTarget(self, action: #selector(toggleConnector(_:)), for: .valueChanged)
        cell.accessoryView = toggle
        return cell
    }

    @objc private func toggleConnector(_ sender: UISwitch) {
        guard let id = sender.accessibilityHint else { return }
        Feedback.toggle(sender.isOn)
        AppSettings.shared.setConnector(id, enabled: sender.isOn)

        guard sender.isOn else { return }
        let alert = UIAlertController(
            title: "Authorise in Notion",
            message: "Connections are authorised in Notion itself. Open the connections page to finish linking this service to your workspace.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Later", style: .cancel))
        alert.addAction(UIAlertAction(title: "Open", style: .default) { _ in
            guard let url = URL(string: NotionEndpoints.host + "/settings/connections") else { return }
            UIApplication.shared.open(url)
        })
        present(alert, animated: true)
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 0 else { return }
        Feedback.tap()

        switch indexPath.row {
        case 0: startImport(source: "ChatGPT")
        case 1: startImport(source: "Claude")
        case 2: startImport(source: "Other assistant")
        default:
            let alert = UIAlertController(
                title: "Clear imported memory?",
                message: "All locally stored facts will be removed.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Clear", style: .destructive) { _ in
                LibraryStore.shared.clearMemories()
                Feedback.warning()
                self.tableView.reloadData()
            })
            present(alert, animated: true)
        }
    }
}

extension ConnectorsViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first, let source = pendingImportSource else { return }
        pendingImportSource = nil

        do {
            let data = try Data(contentsOf: url)
            let count = try LibraryStore.shared.importMemory(from: data, source: source)
            showImportResult("Added \(count) memories from \(source).", success: true)
        } catch {
            showImportResult(error.localizedDescription, success: false)
        }
        tableView.reloadData()
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        pendingImportSource = nil
    }
}
