import UIKit
import WebKit

/// Workspace search. Used both as a browser (tap opens the page) and as a
/// picker for "Reference a page" in the composer.
final class WorkspaceViewController: UIViewController {
    /// When set, the screen acts as a picker instead of a browser.
    var onPick: ((NotionPageSummary) -> Void)?

    private let searchBar = UISearchBar()
    private let table = UITableView(frame: .zero, style: .plain)
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let emptyLabel = UILabel()

    private var results: [NotionPageSummary] = []
    private var debounce: DispatchWorkItem?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = onPick == nil ? "Workspace" : "Reference a page"
        view.backgroundColor = Theme.background

        navigationController?.navigationBar.barTintColor = Theme.surface
        navigationController?.navigationBar.tintColor = Theme.accent
        navigationController?.navigationBar.titleTextAttributes = [
            .foregroundColor: Theme.textPrimary
        ]
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(close)
        )

        searchBar.placeholder = "Search pages"
        searchBar.searchBarStyle = .minimal
        searchBar.barStyle = .black
        searchBar.delegate = self
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchBar)

        table.backgroundColor = Theme.background
        table.separatorColor = Theme.border
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 62
        table.register(UITableViewCell.self, forCellReuseIdentifier: "PageRow")
        table.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(table)

        emptyLabel.text = "Search your Notion workspace"
        emptyLabel.textColor = Theme.textTertiary
        emptyLabel.font = AppSettings.shared.chatFont.font(size: 15)
        emptyLabel.textAlignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)

        spinner.color = Theme.textSecondary
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)

        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),

            table.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 4),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.topAnchor.constraint(equalTo: table.topAnchor, constant: 24)
        ])

        searchBar.becomeFirstResponder()
        runSearch("")
    }

    @objc private func close() {
        dismiss(animated: true, completion: nil)
    }

    private func runSearch(_ query: String) {
        debounce?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.spinner.startAnimating()

            NotionAPI.shared.search(query: query, limit: 25) { result in
                self.spinner.stopAnimating()

                switch result {
                case .success(let pages):
                    self.results = pages
                    self.emptyLabel.isHidden = !pages.isEmpty
                    self.emptyLabel.text = query.isEmpty
                        ? "Search your Notion workspace"
                        : "Nothing found for \u{201C}" + query + "\u{201D}"

                case .failure(let error):
                    self.results = []
                    self.emptyLabel.isHidden = false
                    self.emptyLabel.text = error.localizedDescription
                }

                self.table.reloadData()
            }
        }

        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }
}

extension WorkspaceViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        runSearch(searchText)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

extension WorkspaceViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        results.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "PageRow", for: indexPath)
        let page = results[indexPath.row]

        cell.backgroundColor = Theme.background
        cell.textLabel?.text = (page.iconText.isEmpty ? "" : page.iconText + "  ") + page.title
        cell.textLabel?.textColor = Theme.textPrimary
        cell.textLabel?.font = AppSettings.shared.chatFont.font(size: 16)
        cell.detailTextLabel?.text = page.snippet
        cell.accessoryType = onPick == nil ? .disclosureIndicator : .none
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let page = results[indexPath.row]

        if let onPick = onPick {
            onPick(page)
            dismiss(animated: true, completion: nil)
            return
        }

        navigationController?.pushViewController(PageWebViewController(page: page), animated: true)
    }
}

/// Opens a Notion page inside the app using the stored session cookie.
final class PageWebViewController: UIViewController {
    private let page: NotionPageSummary
    private var webView: WKWebView!
    private let progress = UIProgressView(progressViewStyle: .bar)
    private var observation: NSKeyValueObservation?

    init(page: NotionPageSummary) {
        self.page = page
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = page.title
        view.backgroundColor = Theme.background

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "sparkles"),
            style: .plain,
            target: self,
            action: #selector(askAboutPage)
        )

        webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.backgroundColor = Theme.background
        webView.isOpaque = false
        view.addSubview(webView)
        webView.pinEdges(to: view)

        progress.progressTintColor = Theme.accent
        progress.trackTintColor = .clear
        progress.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(progress)
        NSLayoutConstraint.activate([
            progress.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            progress.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progress.heightAnchor.constraint(equalToConstant: 2)
        ])

        observation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            guard let self = self else { return }
            let value = Float(webView.estimatedProgress)
            self.progress.setProgress(value, animated: !AppSettings.shared.motionReduced)
            self.progress.alpha = value > 0.99 ? 0 : 1
        }

        NotionSession.shared.restoreCookies(into: webView.configuration.websiteDataStore.httpCookieStore) { [weak self] in
            guard let self = self, let url = URL(string: self.page.url) else { return }
            self.webView.load(URLRequest(url: url))
        }
    }

    @objc private func askAboutPage() {
        let prompt = "About the page [" + page.title + "](" + page.url + "): "
        RootController.current?.prefillComposer(with: prompt)
    }
}
