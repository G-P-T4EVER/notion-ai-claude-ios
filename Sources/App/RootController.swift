import UIKit

/// Hosts the chat screen plus the slide-over sidebar. Hand-rolled instead of
/// UISplitViewController so the drawer behaves identically on iOS 14 and 16.
final class RootController: UIViewController {
    static weak var current: RootController?

    private let chat = ChatViewController()
    private let sidebar = SidebarViewController()
    private let dimmer = UIView()

    private let sidebarWidth: CGFloat = 300
    private var sidebarLeading: NSLayoutConstraint!
    private var isSidebarOpen = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        RootController.current = self

        addChild(chat)
        view.addSubview(chat.view)
        chat.view.pinEdges(to: view)
        chat.didMove(toParent: self)

        dimmer.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        dimmer.alpha = 0
        dimmer.isUserInteractionEnabled = false
        view.addSubview(dimmer)
        dimmer.pinEdges(to: view)
        dimmer.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(closeSidebar))
        )

        sidebar.delegate = self
        addChild(sidebar)
        view.addSubview(sidebar.view)
        sidebar.didMove(toParent: self)

        sidebar.view.translatesAutoresizingMaskIntoConstraints = false
        sidebarLeading = sidebar.view.leadingAnchor.constraint(
            equalTo: view.leadingAnchor,
            constant: -sidebarWidth
        )
        NSLayoutConstraint.activate([
            sidebar.view.topAnchor.constraint(equalTo: view.topAnchor),
            sidebar.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sidebar.view.widthAnchor.constraint(equalToConstant: sidebarWidth),
            sidebarLeading
        ])
        sidebar.view.layer.shadowColor = UIColor.black.cgColor
        sidebar.view.layer.shadowOpacity = 0.35
        sidebar.view.layer.shadowRadius = 18
        sidebar.view.layer.shadowOffset = CGSize(width: 2, height: 0)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        view.addGestureRecognizer(pan)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    // MARK: - Sidebar

    func toggleSidebar() {
        setSidebar(open: !isSidebarOpen)
    }

    @objc func closeSidebar() {
        setSidebar(open: false)
    }

    private func setSidebar(open: Bool, velocity: CGFloat = 0) {
        isSidebarOpen = open
        view.endEditing(true)
        if open { sidebar.reload() }

        sidebarLeading.constant = open ? 0 : -sidebarWidth
        dimmer.isUserInteractionEnabled = open

        let animations = {
            self.dimmer.alpha = open ? 1 : 0
            self.view.layoutIfNeeded()
        }

        guard !AppSettings.shared.motionReduced else {
            animations()
            return
        }

        UIView.animate(
            withDuration: 0.34,
            delay: 0,
            usingSpringWithDamping: 0.9,
            initialSpringVelocity: abs(velocity) / sidebarWidth,
            options: [.curveEaseOut],
            animations: animations,
            completion: nil
        )
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view).x

        switch gesture.state {
        case .changed:
            let base: CGFloat = isSidebarOpen ? 0 : -sidebarWidth
            sidebarLeading.constant = min(0, max(-sidebarWidth, base + translation))
            dimmer.alpha = 1 - abs(sidebarLeading.constant) / sidebarWidth

        case .ended, .cancelled:
            let velocity = gesture.velocity(in: view).x
            let progress = 1 - abs(sidebarLeading.constant) / sidebarWidth
            let shouldOpen = velocity > 350 || (velocity > -350 && progress > 0.5)
            setSidebar(open: shouldOpen, velocity: velocity)

        default:
            break
        }
    }

    // MARK: - Navigation helpers

    func startNewChat() {
        chat.loadConversation(nil)
        setSidebar(open: false)
    }

    func open(conversationID: String) {
        chat.loadConversation(conversationID)
        setSidebar(open: false)
    }

    func prefillComposer(with text: String) {
        presentedViewController?.dismiss(animated: true, completion: nil)
        chat.prefill(text)
        setSidebar(open: false)
    }

    func presentSettings(initialSection: SettingsSection = .general) {
        setSidebar(open: false)
        present(
            SettingsHost.makeViewController(initialSection: initialSection),
            animated: !AppSettings.shared.motionReduced,
            completion: nil
        )
    }

    func presentWorkspace() {
        setSidebar(open: false)
        let navigation = UINavigationController(rootViewController: WorkspaceViewController())
        present(navigation, animated: !AppSettings.shared.motionReduced, completion: nil)
    }
}

extension RootController: SidebarDelegate {
    func sidebarDidRequestNewChat() {
        startNewChat()
    }

    func sidebarDidSelect(conversationID: String) {
        open(conversationID: conversationID)
    }

    func sidebarDidRequestSettings() {
        presentSettings()
    }

    func sidebarDidRequestWorkspace() {
        presentWorkspace()
    }
}

extension RootController: UIGestureRecognizerDelegate {
    /// Only start the drawer gesture from the screen edge so chat scrolling and
    /// text selection keep working.
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }

        let translation = pan.translation(in: view)
        guard abs(translation.x) > abs(translation.y) else { return false }

        if isSidebarOpen { return true }
        return pan.location(in: view).x < 40
    }
}
