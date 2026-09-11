import UIKit
import WebKit

/// Sign-in happens on notion.so itself: email code, Google, Apple and SSO all
/// work because it is the real login page. Once Notion sets `token_v2` the
/// cookie is copied into the keychain and the web view is dismissed.
final class LoginViewController: UIViewController {
    private var webView: WKWebView!
    private let progress = UIProgressView(progressViewStyle: .bar)
    private let splash = UIView()
    private let mark = StarburstView()
    private let statusLabel = UILabel()
    private var progressObservation: NSKeyValueObservation?
    private var didCapture = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.backgroundColor = Theme.background
        webView.isOpaque = false
        webView.scrollView.backgroundColor = Theme.background
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

        buildSplash()

        progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            guard let self = self else { return }
            let value = Float(webView.estimatedProgress)
            self.progress.setProgress(value, animated: !AppSettings.shared.motionReduced)
            self.progress.alpha = value > 0.99 ? 0 : 1
        }

        webView.load(URLRequest(url: NotionEndpoints.loginURL))
    }

    private func buildSplash() {
        splash.backgroundColor = Theme.background
        view.addSubview(splash)
        splash.pinEdges(to: view)

        mark.color = Theme.accent
        mark.translatesAutoresizingMaskIntoConstraints = false
        splash.addSubview(mark)

        statusLabel.text = "Signing in to Notion"
        statusLabel.textColor = Theme.textSecondary
        statusLabel.font = ChatFontChoice.anthropicSerif.font(size: 17)
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        splash.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            mark.centerXAnchor.constraint(equalTo: splash.centerXAnchor),
            mark.centerYAnchor.constraint(equalTo: splash.centerYAnchor, constant: -24),
            mark.widthAnchor.constraint(equalToConstant: 56),
            mark.heightAnchor.constraint(equalToConstant: 56),
            statusLabel.topAnchor.constraint(equalTo: mark.bottomAnchor, constant: 20),
            statusLabel.leadingAnchor.constraint(equalTo: splash.leadingAnchor, constant: 32),
            statusLabel.trailingAnchor.constraint(equalTo: splash.trailingAnchor, constant: -32)
        ])

        splash.isHidden = true
    }

    private func setSplash(visible: Bool, message: String? = nil) {
        if let message = message { statusLabel.text = message }
        splash.isHidden = !visible
        visible ? mark.startSpinning() : mark.stopSpinning()
    }

    private func captureTokenIfPossible() {
        guard !didCapture else { return }

        NotionSession.captureToken(from: webView.configuration.websiteDataStore.httpCookieStore) { [weak self] captured in
            guard let self = self, captured, !self.didCapture else { return }
            self.didCapture = true
            self.finishSignIn()
        }
    }

    private func finishSignIn() {
        setSplash(visible: true, message: "Loading your workspace")

        NotionAPI.shared.loadUserContent { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success:
                Haptics.success()
                NotificationCenter.default.post(name: NotionSession.didChangeNotification, object: nil)

            case .failure(let error):
                self.didCapture = false
                self.setSplash(visible: false)
                Haptics.warning()

                let alert = UIAlertController(
                    title: "Could not finish sign-in",
                    message: error.localizedDescription,
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "Try again", style: .default) { _ in
                    self.webView.load(URLRequest(url: NotionEndpoints.loginURL))
                })
                alert.addAction(UIAlertAction(title: "Continue anyway", style: .cancel) { _ in
                    NotificationCenter.default.post(
                        name: NotionSession.didChangeNotification,
                        object: nil
                    )
                })
                self.present(alert, animated: true, completion: nil)
            }
        }
    }
}

extension LoginViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        captureTokenIfPossible()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        decisionHandler(.allow)
        captureTokenIfPossible()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        progress.alpha = 0
    }
}
