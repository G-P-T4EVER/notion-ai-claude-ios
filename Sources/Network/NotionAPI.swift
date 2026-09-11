import Foundation

final class NotionAPI {
    static let shared = NotionAPI()

    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        configuration.httpShouldSetCookies = true
        session = URLSession(configuration: configuration)
    }

    // MARK: - Low level

    private func post(
        path: String,
        body: [String: Any],
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        let request: URLRequest
        do {
            request = try NotionSession.shared.authorizedRequest(path: path, body: body)
        } catch {
            completion(.failure(error))
            return
        }

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(NotionError.transport(error.localizedDescription)))
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 || status == 403 {
                completion(.failure(NotionError.sessionExpired))
                return
            }
            guard (200..<300).contains(status) else {
                completion(.failure(NotionError.http(status)))
                return
            }
            guard
                let data = data,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                completion(.failure(NotionError.malformedResponse))
                return
            }
            completion(.success(json))
        }.resume()
    }

    /// Notion wraps records either as `{ value: {...} }` or `{ value: { value: {...} } }`.
    private static func unwrap(_ record: Any?) -> [String: Any]? {
        guard let record = record as? [String: Any] else { return nil }
        if let inner = record["value"] as? [String: Any] {
            if let deeper = inner["value"] as? [String: Any] { return deeper }
            return inner
        }
        return record
    }

    private static func records(in recordMap: [String: Any], table: String) -> [[String: Any]] {
        guard let bucket = recordMap[table] as? [String: Any] else { return [] }
        return bucket.values.compactMap { unwrap($0) }
    }

    // MARK: - Identity and spaces

    /// Loads the signed-in user, their email and all spaces, and caches them on the session.
    func loadUserContent(completion: @escaping (Result<NotionSpace?, Error>) -> Void) {
        loadSpaces { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let spaces):
                let current = spaces.first(where: { $0.id == NotionSession.shared.spaceID }) ?? spaces.first
                completion(.success(current))
            }
        }
    }

    /// Returns every space the account can open, and fills in profile fields.
    func loadSpaces(completion: @escaping (Result<[NotionSpace], Error>) -> Void) {
        post(path: "loadUserContent", body: [:]) { result in
            switch result {
            case .failure(let error):
                DispatchQueue.main.async { completion(.failure(error)) }
            case .success(let json):
                guard let recordMap = json["recordMap"] as? [String: Any] else {
                    DispatchQueue.main.async { completion(.failure(NotionError.malformedResponse)) }
                    return
                }

                // Profile: notion_user holds the name, user_settings / email holds the address.
                var name: String?
                var email: String?
                var userID: String?

                for user in NotionAPI.records(in: recordMap, table: "notion_user") {
                    let given = (user["given_name"] as? String) ?? ""
                    let family = (user["family_name"] as? String) ?? ""
                    let full = [given, family]
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                        .trimmingCharacters(in: .whitespaces)
                    let candidate = full.isEmpty ? (user["name"] as? String) : full
                    if let candidate = candidate, !candidate.isEmpty, name == nil {
                        name = candidate
                        userID = user["id"] as? String
                    }
                    if email == nil, let mail = user["email"] as? String, !mail.isEmpty {
                        email = mail
                    }
                }

                if email == nil {
                    for settings in NotionAPI.records(in: recordMap, table: "user_settings") {
                        if let mail = settings["email"] as? String, !mail.isEmpty {
                            email = mail
                            break
                        }
                        if let nested = settings["settings"] as? [String: Any],
                           let mail = nested["email"] as? String, !mail.isEmpty {
                            email = mail
                            break
                        }
                    }
                }

                if email == nil {
                    for root in NotionAPI.records(in: recordMap, table: "user_root") {
                        if let mail = root["email"] as? String, !mail.isEmpty {
                            email = mail
                            break
                        }
                    }
                }

                var spaces: [NotionSpace] = []
                for space in NotionAPI.records(in: recordMap, table: "space") {
                    guard
                        let id = space["id"] as? String,
                        let spaceName = space["name"] as? String
                    else { continue }
                    spaces.append(NotionSpace(id: id, name: spaceName, icon: space["icon"] as? String))
                }
                spaces.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

                DispatchQueue.main.async {
                    let session = NotionSession.shared
                    if let name = name { session.userName = name }
                    if let email = email { session.userEmail = email }
                    if let userID = userID, session.userID == nil { session.userID = userID }

                    if let currentID = session.spaceID,
                       let match = spaces.first(where: { $0.id == currentID }) {
                        session.spaceName = match.name
                    } else if let first = spaces.first {
                        session.spaceID = first.id
                        session.spaceName = first.name
                    }
                    NotificationCenter.default.post(name: NotionSession.didChangeNotification, object: nil)
                    completion(.success(spaces))
                }
            }
        }
    }

    func switchSpace(to space: NotionSpace) {
        let session = NotionSession.shared
        session.spaceID = space.id
        session.spaceName = space.name
        NotificationCenter.default.post(name: NotionSession.didChangeNotification, object: nil)
    }

    // MARK: - Search

    func search(
        query: String,
        limit: Int = 20,
        completion: @escaping (Result<[NotionPageSummary], Error>) -> Void
    ) {
        guard let spaceID = NotionSession.shared.spaceID else {
            completion(.failure(NotionError.notAuthenticated))
            return
        }

        let body: [String: Any] = [
            "type": "BlocksInSpace",
            "query": query,
            "spaceId": spaceID,
            "limit": limit,
            "filters": [
                "isDeletedOnly": false,
                "excludeTemplates": false,
                "isNavigableOnly": false,
                "requireEditPermissions": false,
                "ancestors": [],
                "createdBy": [],
                "editedBy": [],
                "lastEditedTime": [:],
                "createdTime": [:]
            ],
            "sort": ["field": "relevance"],
            "source": "quick_find_input_change"
        ]

        post(path: "search", body: body) { result in
            switch result {
            case .failure(let error):
                DispatchQueue.main.async { completion(.failure(error)) }
            case .success(let json):
                let recordMap = (json["recordMap"] as? [String: Any]) ?? [:]
                var blocks: [String: [String: Any]] = [:]
                if let bucket = recordMap["block"] as? [String: Any] {
                    for (key, value) in bucket {
                        if let record = NotionAPI.unwrap(value) { blocks[key] = record }
                    }
                }

                var pages: [NotionPageSummary] = []
                let results = (json["results"] as? [[String: Any]]) ?? []
                for item in results {
                    guard let id = item["id"] as? String else { continue }
                    let block = blocks[id]
                    let title = NotionAPI.plainTitle(from: block)
                        ?? (((item["highlight"] as? [String: Any])?["pathText"] as? String) ?? "Untitled")
                    var snippet = ""
                    if let highlight = item["highlight"] as? [String: Any],
                       let text = highlight["text"] as? String {
                        snippet = text
                            .replacingOccurrences(of: "<gzkNfoUU>", with: "")
                            .replacingOccurrences(of: "</gzkNfoUU>", with: "")
                    }
                    let slug = id.replacingOccurrences(of: "-", with: "")
                    let icon = (block?["format"] as? [String: Any])?["page_icon"] as? String
                    pages.append(
                        NotionPageSummary(
                            id: id,
                            title: title.isEmpty ? "Untitled" : title,
                            icon: icon,
                            url: NotionEndpoints.host + "/" + slug,
                            snippet: snippet
                        )
                    )
                }
                DispatchQueue.main.async { completion(.success(pages)) }
            }
        }
    }

    // MARK: - Page content

    func loadPageText(pageID: String, completion: @escaping (Result<String, Error>) -> Void) {
        let body: [String: Any] = [
            "pageId": pageID,
            "limit": 80,
            "cursor": ["stack": []],
            "chunkNumber": 0,
            "verticalColumns": false
        ]

        post(path: "loadPageChunk", body: body) { result in
            switch result {
            case .failure(let error):
                DispatchQueue.main.async { completion(.failure(error)) }
            case .success(let json):
                guard
                    let recordMap = json["recordMap"] as? [String: Any],
                    let bucket = recordMap["block"] as? [String: Any]
                else {
                    DispatchQueue.main.async { completion(.failure(NotionError.malformedResponse)) }
                    return
                }

                var lines: [String] = []
                for value in bucket.values {
                    guard let block = NotionAPI.unwrap(value) else { continue }
                    if let title = NotionAPI.plainTitle(from: block), !title.isEmpty {
                        lines.append(title)
                    }
                }
                DispatchQueue.main.async {
                    completion(.success(lines.joined(separator: "\n")))
                }
            }
        }
    }

    /// Pulls a short workspace context block for the current question.
    func contextSnippet(for query: String, completion: @escaping (String) -> Void) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 3, NotionSession.shared.spaceID != nil else {
            completion("")
            return
        }
        search(query: trimmed, limit: 5) { result in
            guard case .success(let pages) = result, !pages.isEmpty else {
                completion("")
                return
            }
            let lines = pages.prefix(5).map { page -> String in
                let snippet = page.snippet.isEmpty ? "" : " — " + String(page.snippet.prefix(180))
                return "- \(page.title)\(snippet)"
            }
            completion(lines.joined(separator: "\n"))
        }
    }

    static func plainTitle(from block: [String: Any]?) -> String? {
        guard let block = block else { return nil }
        guard let properties = block["properties"] as? [String: Any] else { return nil }
        guard let title = properties["title"] as? [[Any]] else { return nil }
        var text = ""
        for run in title {
            if let piece = run.first as? String { text += piece }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
