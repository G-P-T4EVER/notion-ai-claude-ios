import UIKit

/// Model + effort picker, grouped by provider with small provider marks.
final class ModelPickerViewController: UIViewController {
    var onChange: ((AIModel, ModelEffort) -> Void)?

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var selectedModel: AIModel
    private var selectedEffort: ModelEffort
    private let groups = AIModel.grouped()

    init(model: AIModel, effort: ModelEffort) {
        self.selectedModel = model
        self.selectedEffort = effort
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        title = "Model"

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(done)
        )

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = Theme.background
        tableView.separatorColor = Theme.border
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 62
        view.addSubview(tableView)
        tableView.pinEdges(to: view)
    }

    @objc private func done() {
        Feedback.tap()
        dismiss(animated: true)
    }

    private var effortSection: Int { 0 }

    private func commit() {
        onChange?(selectedModel, selectedEffort)
    }
}

extension ModelPickerViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        groups.count + 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == effortSection {
            return selectedModel.supportsEffort ? selectedModel.efforts.count : 1
        }
        return groups[section - 1].models.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == effortSection { return "EFFORT" }
        return groups[section - 1].provider.title.uppercased()
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard section == effortSection else { return nil }
        return selectedModel.supportsEffort
            ? "Higher effort means more reasoning time for \(selectedModel.name)."
            : "\(selectedModel.name) runs at a fixed effort."
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.backgroundColor = Theme.surface
        cell.textLabel?.textColor = Theme.textPrimary
        cell.detailTextLabel?.textColor = Theme.textTertiary
        cell.detailTextLabel?.numberOfLines = 2
        cell.textLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        cell.detailTextLabel?.font = .systemFont(ofSize: 12)
        cell.selectedBackgroundView = {
            let view = UIView()
            view.backgroundColor = Theme.surfaceRaised
            return view
        }()

        if indexPath.section == effortSection {
            let effort = selectedModel.supportsEffort
                ? selectedModel.efforts[indexPath.row]
                : selectedModel.defaultEffort
            cell.textLabel?.text = effort.title
            cell.detailTextLabel?.text = effort.detail
            cell.imageView?.image = UIImage(systemName: effort.symbol)
            cell.imageView?.tintColor = Theme.textSecondary
            cell.accessoryType = effort == selectedEffort ? .checkmark : .none
            cell.tintColor = Theme.accent
            return cell
        }

        let model = groups[indexPath.section - 1].models[indexPath.row]
        cell.textLabel?.text = model.name
        cell.detailTextLabel?.text = model.tier.title.uppercased() + " · " + model.blurb
        cell.imageView?.image = ProviderMark.image(for: model.provider, size: 22)
        cell.accessoryType = model.id == selectedModel.id ? .checkmark : .none
        cell.tintColor = Theme.accent
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        Feedback.selection()

        if indexPath.section == effortSection {
            guard selectedModel.supportsEffort else { return }
            selectedEffort = selectedModel.efforts[indexPath.row]
            tableView.reloadSections(IndexSet(integer: effortSection), with: .none)
            commit()
            return
        }

        let model = groups[indexPath.section - 1].models[indexPath.row]
        selectedModel = model
        if !model.efforts.contains(selectedEffort) {
            selectedEffort = model.defaultEffort
        }
        tableView.reloadData()
        commit()
    }

    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        guard let header = view as? UITableViewHeaderFooterView else { return }
        header.textLabel?.textColor = Theme.textTertiary
        header.textLabel?.font = .systemFont(ofSize: 11, weight: .semibold)
    }

    func tableView(_ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int) {
        guard let footer = view as? UITableViewHeaderFooterView else { return }
        footer.textLabel?.textColor = Theme.textTertiary
        footer.textLabel?.font = .systemFont(ofSize: 12)
    }
}
