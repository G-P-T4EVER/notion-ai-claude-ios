import Foundation
import WebKit

enum NotionEndpoints {
    static let domain = "www." + "notion" + ".so"
    static let host = "https://" + domain
    static let loginURL = URL(string: host + "/login")!

    /// Notion does not publish an AI endpoint. This is the transcript endpoint
    /// the web client has historically used; it is overridable in Settings ->
    /// Capabilities so a server-side rename does not brick the app.
    static let defaultAIPath = "runInferenceTranscript"

    static func api(_ path: String) -> URL {
        URL(string: host + "/api/v3/" + path)!
    }
}

/// Holds the authenticated Notion session: the `token_v2` cookie captured from
/// the official login page, plus the ids every /api/v3 call needs.
final class NotionSession {
    static let shared = NotionSession()

    static let didChangeNotification = Notification.Name("NotionSessionDidChange")

    private enum Account {
        static let token = "token_v2"
    }

    private let defaults = UserDefaults.standard

    private(set) var token: String? {
        didSet { Keychain.set(token, for: Account.token) }
    }

    var userID: String? {
        get { defaults.string(forKey: "session.userID") }
        set { defaults.set(newValue, forKey: "session.userID") }
    }

    var spaceID: String? {
        get { defaults.string(forKey: "session.spaceID") }
        set { defaults.set(newValue, forKey: "session.spaceID") }
    }

    var spaceName: String? {
        get { defaults.string(forKey: "session.spaceName") }
        set { defaults.set(newValue, forKey: "session.spaceName") }
    }

    var userName: String? {
        get { defaults.string(forKey: "session.userName") }
        set { defaults.set(newValue, forKey: "session.userName") }
    }

    var userEmail: String? {
        get { defaults.string(forKey: "session.userEmail") }
        set { defaults.set(newValue, forKey: "session.userEmail") }
    }

    var isAuthenticated: Bool {
        !(token ?? "").isEmpty
    }

    private init() {
        token = Keychain.get(Account.token)
    }

    func store(token newToken: String) {
        token = newToken
        NotificationCenter.default.post(name: NotionSession.didChangeNotification, object: nil)
    }

    func signOut(completion: (() -> Void)? = nil) {
        token = nil
        userID = nil
        spaceID = nil
        spaceName = nil
        userName = nil
        userEmail = nil

        let store = WKWebsiteDataStore.default()
        store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            let notionRecords = records.filter { $0.displayName.contains("notion") }
            store.removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                for: notionRecords
            ) {
                NotificationCenter.default.post(name: NotionSession.didChangeNotification, object: nil)
                completion?()
            }
        }
    }

    /// Pulls `token_v2` out of the web view cookie jar after an official login.
    static func captureToken(from cookieStore: WKHTTPCookieStore, completion: @escaping (Bool) -> Void) {
        cookieStore.getAllCookies { cookies in
            guard let cookie = cookies.first(where: { $0.name == "token_v2" }), !cookie.value.isEmpty else {
                completion(false)
                return
            }
            NotionSession.shared.store(token: cookie.value)
            completion(true)
        }
    }

    /// Injects the stored session cookie into a web view so in-app page reading
    /// works without a second sign-in.
    func restoreCookies(into cookieStore: WKHTTPCookieStore, completion: @escaping () -> Void) {
        guard
            let token = token,
            !token.isEmpty,
            let cookie = HTTPCookie(properties: [
                .domain: "." + NotionEndpoints.domain.replacingOccurrences(of: "www.", with: ""),
                .path: "/",
                .name: "token_v2",
                .value: token,
                .secure: "TRUE",
                .expires: Date(timeIntervalSinceNow: 60 * 60 * 24 * 180)
            ])
        else {
            completion()
            return
        }

        cookieStore.setCookie(cookie) {
            completion()
        }
    }

    func authorizedRequest(path: String, body: [String: Any]) throws -> URLRequest {
        guard let token = token, !token.isEmpty else { throw NotionError.notAuthenticated }

        var request = URLRequest(url: NotionEndpoints.api(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("token_v2=" + token, forHTTPHeaderField: "Cookie")
        request.setValue(NotionEndpoints.host, forHTTPHeaderField: "Origin")
        request.setValue(NotionEndpoints.host + "/", forHTTPHeaderField: "Referer")
        request.setValue("web", forHTTPHeaderField: "notion-audit-log-platform")
        request.setValue("ios", forHTTPHeaderField: "notion-client-version-platform")
        if let userID = userID {
            request.setValue(userID, forHTTPHeaderField: "x-notion-active-user-header")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        return request
    }
}

enum NotionError: LocalizedError {
    case notAuthenticated
    case sessionExpired
    case http(Int)
    case malformedResponse
    case endpointUnavailable(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You are signed out. Sign in with your Notion account to continue."
        case .sessionExpired:
            return "Your Notion session expired. Please sign in again."
        case .http(let code):
            return "Notion returned HTTP " + String(code) + "."
        case .malformedResponse:
            return "Notion returned a response this build could not read."
        case .endpointUnavailable(let path):
            return "Notion no longer serves '" + path + "'. Update the AI endpoint in Settings -> Capabilities."
        case .transport(let message):
            return message
        }
    }
}
