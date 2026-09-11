import UIKit

final class RootController: UIViewController {
    static weak var current: RootController?

    private let header = UIView()
    private let menuButton = UIButton(type: .system)
    private let workspaceButton = UIButton(type: .system)
    private let newChatButton = UIButton(type: .system)

    private let chat = ChatViewController()
    private let sidebar = SidebarViewController()
    private let dimView = UIView()

    private let sidebarWidth: CGFloat = 300
    private var sidebarLeading: NSLayoutConstraint!
    private var isSidebarOpen = false

    override func viewDidLoad() {
        super.viewDidLoad()
        RootController.current = self
        view.backgroundColor = Theme.background

        buildHeader()
        buildChat()
        buildSidebar()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionChanged),
            name: NotionSession.didChangeNotification,
            object: nil
        )

        refreshWorkspaceButton()
        loadProfile()
    }

    // MARK: - Build

    private func buildHeader() {
        header.translatesAutoresizingMaskIntoConstraints = false
        header.backgroundColor = Theme.background
        view.addSubview(header)

        menuButton.translatesAutoresizingMaskIntoConstraints = false
        menuButton.setImage(UIImage(systemName: "line.3.horizontal"), for: .normal)
        menuButton.tintColor = Theme.textSecondary
        menuButton.addTarget(self, action: #selector(menuTapped), for: .touchUpInside)
        header.addSubview(menuButton)

        workspaceButton.translatesAutoresizingMaskIntoConstraints = false
        workspaceButton.setTitleColor(Theme.textPrimary, for: .normal)
        workspaceButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        workspaceButton.tintColor = Theme.textTertiary
        workspaceButton.semanticContentAttribute = .forceRightToLeft
        workspaceButton.setImage(UIImage(systemName: "chevron.down"), for: .normal)
        workspaceButton.imageEdgeInsets = UIEdgeInsets(top: 1, left: 6, bottom: 0, right: 0)
        workspaceButton.addTarget(self, action: #selector(workspaceTapped), for: .touchUpInside)
        header.addSubview(workspaceButton)

        newChatButton.translatesAutoresizingMaskIntoConstraints = false
        newChatButton.setImage(UIImage(systemName: "square.and.pencil"), for: .normal)
        newChatButton.tintColor = Theme.textSecondary
        newChatButton.addTarget(self, action: #selector(newChatTapped), for: .touchUpInside)
        header.addSubview(newChatButton)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 48),

            menuButton.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 12),
            menuButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            menuButton.widthAnchor.constraint(equalToConstant: 36),
            menuButton.heightAnchor.constraint(equalToConstant: 36),

            workspaceButton.leadingAnchor.constraint(equalTo: menuButton.trailingAnchor, constant: 4),
            workspaceButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            workspaceButton.trailingAnchor.constraint(lessThanOrEqualTo: newChatButton.leadingAnchor, constant: -8),

            newChatButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -12),
            newChatButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            newChatButton.widthAnchor.constraint(equalToConstant: 36),
            newChatButton.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    private func buildChat() {
        addChild(chat)
        chat.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(chat.view)
        chat.didMove(toParent: self)

        NSLayoutConstraint.activate([
            chat.view.topAnchor.constraint(equalTo: header.bottomAnchor),
            chat.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chat.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chat.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func buildSidebar() {
        dimView.translatesAutoresizingMaskIntoConstraints = false
        dimView.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        dimView.alpha = 0
        dimView.isUserInteractionEnabled = false
        view.addSubview(dimView)
        dimView.pinEdges(to: view)
        dimView.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(closeSidebarTapped))
        )

        sidebar.delegate = self
        addChild(sidebar)
        sidebar.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sidebar.view)
        sidebar.didMove(toParent: self)

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

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        view.addGestureRecognizer(pan)
    }

    // MARK: - Session

    @objc private func sessionChanged() {
        refreshWorkspaceButton()
    }

    private func refreshWorkspaceButton() {
        let name = NotionSession.shared.spaceName
        workspaceButton.setTitle(name?.isEmpty == false ? name : "Notion AI", for: .normal)
    }

    private func loadProfile() {
        guard NotionSession.shared.isAuthenticated else { return }
        NotionAPI.shared.loadUserContent { [weak self] _ in
            self?.refreshWorkspaceButton()
        }
    }

    // MARK: - Sidebar

    func toggleSidebar() {
        setSidebar(open: !isSidebarOpen)
    }

    func closeSidebar() {
        setSidebar(open: false)
    }

    private func setSidebar(open: Bool) {
        isSidebarOpen = open
        sidebarLeading.constant = open ? 0 : -sidebarWidth
        dimView.isUserInteractionEnabled = open

        let animations = {
            self.dimView.alpha = open ? 1 : 0
            self.view.layoutIfNeeded()
        }

        if AppSettings.shared.motionReduced {
            animations()
        } else {
            UIView.animate(
                withDuration: 0.32,
                delay: 0,
                usingSpringWithDamping: 0.86,
                initialSpringVelocity: 0.4,
                options: [.curveEaseOut],
                animations: animations
            )
        }
    }

    @objc private func closeSidebarTapped() {
        Feedback.tap()
        closeSidebar()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view).x

        switch gesture.state {
        case .changed:
            let base: CGFloat = isSidebarOpen ? 0 : -sidebarWidth
            sidebarLeading.constant = min(0, max(-sidebarWidth, base + translation))
            dimView.alpha = 1 + sidebarLeading.constant / sidebarWidth
        case .ended, .cancelled:
            let velocity = gesture.velocity(in: view).x
            let shouldOpen = velocity > 250
                || (velocity > -250 && sidebarLeading.constant > -sidebarWidth / 2)
            if shouldOpen != isSidebarOpen { Feedback.sheet() }
            setSidebar(open: shouldOpen)
        default:
            break
        }
    }

    // MARK: - Actions

    @objc private func menuTapped() {
        Feedback.tap()
        toggleSidebar()
    }

    @objc private func newChatTapped() {
        Feedback.tap()
        startNewChat()
    }

    @objc private func workspaceTapped() {
        Feedback.tap()
        presentWorkspaceSwitcher()
    }

    func startNewChat() {
        chat.loadConversation(nil)
        closeSidebar()
    }

    func open(conversationID: String) {
        chat.loadConversation(conversationID)
        closeSidebar()
    }

    func prefillComposer(with text: String) {
        chat.prefill(text)
    }

    func presentSettings(initialSection: SettingsSection = .general) {
        Feedback.sheet()
        closeSidebar()
        let controller = SettingsHost.makeViewController(initialSection: initialSection)
        controller.modalPresentationStyle = .fullScreen
        topPresenter().present(controller, animated: true)
    }

    func presentWorkspace() {
        Feedback.sheet()
        closeSidebar()
        let workspace = WorkspaceViewController()
        workspace.onPick = { [weak self] page in
            self?.prefillComposer(with: "About the page \"\(page.title)\": ")
        }
        topPresenter().present(UINavigationController(rootViewController: workspace), animated: true)
    }

    func presentWorkspaceSwitcher() {
        closeSidebar()
        let switcher = WorkspaceSwitcherViewController()
        switcher.onSwitch = { [weak self] _ in
            self?.refreshWorkspaceButton()
            self?.startNewChat()
        }
        topPresenter().present(UINavigationController(rootViewController: switcher), animated: true)
    }

    private func topPresenter() -> UIViewController {
        var controller: UIViewController = self
        while let presented = controller.presentedViewController, !presented.isBeingDismissed {
            controller = presented
        }
        return controller
    }
}

extension RootController: SidebarDelegate {
    func sidebarDidRequestNewChat() {
        Feedback.tap()
        startNewChat()
    }

    func sidebarDidSelect(conversationID: String) {
        Feedback.selection()
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
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: view)
        guard abs(velocity.x) > abs(velocity.y) else { return false }
        if isSidebarOpen { return true }
        return pan.location(in: view).x < 40
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        false
    }
}
