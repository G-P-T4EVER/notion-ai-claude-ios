import Foundation

/// Thin wrapper over the private /api/v3 surface the Notion web client uses.
/// Everything here is best-effort and defensively parsed: the endpoints are
/// undocumented and can change without notice.
final class NotionAPI {
    static let shared = NotionAPI()

    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    private func post(
        _ path: String,
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
            if status == 404 {
                completion(.failure(NotionError.endpointUnavailable(path)))
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

    private func main(_ block: @escaping () -> Void) {
        DispatchQueue.main.async(execute: block)
    }

    /// Resolves the signed-in user and their default workspace.
    func loadUserContent(completion: @escaping (Result<NotionSpace?, Error>) -> Void) {
        post("loadUserContent", body: [:]) { result in
            switch result {
            case .failure(let error):
                self.main { completion(.failure(error)) }
            case .success(let json):
                let recordMap = json["recordMap"] as? [String: Any] ?? [:]

                if let users = recordMap["notion_user"] as? [String: Any],
                   let first = users.values.compactMap({ ($0 as? [String: Any])?["value"] as? [String: Any] }).first {
                    NotionSession.shared.userID = first["id"] as? String
                    let given = first["given_name"] as? String ?? ""
                    let family = first["family_name"] as? String ?? ""
                    let name = (given + " " + family).trimmingCharacters(in: .whitespaces)
                    NotionSession.shared.userName = name.isEmpty ? first["name"] as? String : name
                    NotionSession.shared.userEmail = first["email"] as? String
                }

                var space: NotionSpace?
                if let spaces = recordMap["space"] as? [String: Any] {
                    let values = spaces.values.compactMap { ($0 as? [String: Any])?["value"] as? [String: Any] }
                    if let first = values.first, let id = first["id"] as? String {
                        space = NotionSpace(
                            id: id,
                            name: first["name"] as? String ?? "Workspace",
                            icon: first["icon"] as? String
                        )
                        NotionSession.shared.spaceID = id
                        NotionSession.shared.spaceName = space?.name
                    }
                }

                self.main { completion(.success(space)) }
            }
        }
    }

    /// Full-text search across the workspace, used by the Workspace tab and by
    /// Cowork mode to ground answers in real pages.
    func search(
        query: String,
        limit: Int = 20,
        completion: @escaping (Result<[NotionPageSummary], Error>) -> Void
    ) {
        guard let spaceID = NotionSession.shared.spaceID else {
            main { completion(.failure(NotionError.notAuthenticated)) }
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

        post("search", body: body) { result in
            switch result {
            case .failure(let error):
                self.main { completion(.failure(error)) }
            case .success(let json):
                let recordMap = json["recordMap"] as? [String: Any] ?? [:]
                let blocks = recordMap["block"] as? [String: Any] ?? [:]
                let results = json["results"] as? [[String: Any]] ?? []

                var pages: [NotionPageSummary] = []
                for item in results {
                    guard let id = item["id"] as? String else { continue }
                    let block = (blocks[id] as? [String: Any])?["value"] as? [String: Any]
                    let title = NotionAPI.plainTitle(from: block) ?? "Untitled"
                    let slug = id.replacingOccurrences(of: "-", with: "")
                    pages.append(
                        NotionPageSummary(
                            id: id,
                            title: title,
                            icon: block?["format"].flatMap { ($0 as? [String: Any])?["page_icon"] as? String },
                            url: NotionEndpoints.host + "/" + slug
                        )
                    )
                }
                self.main { completion(.success(pages)) }
            }
        }
    }

    /// Reads a page's text so Cowork mode can quote real content.
    func loadPageText(pageID: String, completion: @escaping (Result<String, Error>) -> Void) {
        let body: [String: Any] = [
            "pageId": pageID,
            "limit": 100,
            "cursor": ["stack": []],
            "chunkNumber": 0,
            "verticalColumns": false
        ]

        post("loadPageChunk", body: body) { result in
            switch result {
            case .failure(let error):
                self.main { completion(.failure(error)) }
            case .success(let json):
                let recordMap = json["recordMap"] as? [String: Any] ?? [:]
                let blocks = recordMap["block"] as? [String: Any] ?? [:]
                var lines: [String] = []
                for entry in blocks.values {
                    guard
                        let value = (entry as? [String: Any])?["value"] as? [String: Any],
                        let text = NotionAPI.plainTitle(from: value),
                        !text.isEmpty
                    else { continue }
                    lines.append(text)
                }
                self.main { completion(.success(lines.joined(separator: "\n"))) }
            }
        }
    }

    /// Notion rich text is an array of `[text, annotations]` tuples.
    static func plainTitle(from block: [String: Any]?) -> String? {
        guard
            let properties = block?["properties"] as? [String: Any],
            let title = properties["title"] as? [[Any]]
        else { return nil }

        return title.compactMap { $0.first as? String }.joined()
    }
}
