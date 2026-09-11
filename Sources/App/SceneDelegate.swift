import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        window.backgroundColor = Theme.background
        window.overrideUserInterfaceStyle = .dark
        window.tintColor = Theme.accent
        window.rootViewController = SceneDelegate.makeRoot()
        window.makeKeyAndVisible()
        self.window = window

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionDidChange),
            name: NotionSession.didChangeNotification,
            object: nil
        )
    }

    static func makeRoot() -> UIViewController {
        NotionSession.shared.isAuthenticated ? RootController() : LoginViewController()
    }

    @objc private func sessionDidChange() {
        guard let window = window else { return }

        let root = SceneDelegate.makeRoot()

        guard !AppSettings.shared.motionReduced else {
            window.rootViewController = root
            return
        }

        UIView.transition(with: window, duration: 0.3, options: [.transitionCrossDissolve], animations: {
            window.rootViewController = root
        })
    }
}
