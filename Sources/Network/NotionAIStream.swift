import Foundation

/// Streams an assistant reply from Notion AI.
///
/// The response is newline-delimited JSON. Shapes have changed over time, so the
/// parser walks whatever object arrives and extracts any text-bearing field
/// instead of insisting on one schema.
final class NotionAIStream: NSObject {
    struct Request {
        var messages: [ChatMessage]
        var mode: ChatMode
        var model: AIModel
        var conversationID: String
        var workspaceContext: String?
    }

    private var session: URLSession!
    private var task: URLSessionDataTask?
    private var buffer = Data()
    private var accumulated = ""
    private var finished = false

    private var onDelta: ((String) -> Void)?
    private var onActivity: ((ActivityNote) -> Void)?
    private var onFinish: ((Result<String, Error>) -> Void)?

    override init() {
        super.init()
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 180
        configuration.timeoutIntervalForResource = 600
        configuration.httpCookieStorage = nil
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    var isRunning: Bool {
        task?.state == .running
    }

    func start(
        _ request: Request,
        onDelta: @escaping (String) -> Void,
        onActivity: @escaping (ActivityNote) -> Void,
        onFinish: @escaping (Result<String, Error>) -> Void
    ) {
        self.onDelta = onDelta
        self.onActivity = onActivity
        self.onFinish = onFinish
        buffer = Data()
        accumulated = ""
        finished = false

        let path = AppSettings.shared.aiEndpointPath
        do {
            let urlRequest = try NotionSession.shared.authorizedRequest(
                path: path,
                body: body(for: request)
            )
            task = session.dataTask(with: urlRequest)
            task?.resume()
        } catch {
            complete(.failure(error))
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        guard !finished else { return }
        finished = true
        let partial = accumulated
        DispatchQueue.main.async { [weak self] in
            self?.onFinish?(.success(partial))
        }
    }

    private func body(for request: Request) -> [String: Any] {
        let transcript: [[String: Any]] = request.messages.compactMap { message in
            guard !message.text.isEmpty else { return nil }
            return [
                "type": message.role == .user ? "human" : "assistant",
                "id": message.id,
                "value": [[[message.text]]],
                "userId": NotionSession.shared.userID ?? ""
            ]
        }

        var body: [String: Any] = [
            "version": 1,
            "id": request.conversationID,
            "spaceId": NotionSession.shared.spaceID ?? "",
            "model": request.model.id,
            "createThread": false,
            "traceId": UUID().uuidString,
            "transcript": transcript,
            "debugOverrides": [
                "cachedInferences": [:],
                "annotationInferences": [:],
                "emitInferences": false
            ],
            "generateTitle": true,
            "saveAllThreadOperations": false
        ]

        // Cowork mode is the only mode allowed to look at workspace content.
        if request.mode == .cowork {
            body["searchScopes"] = [["type": "notion"], ["type": "web"]]
            if let context = request.workspaceContext, !context.isEmpty {
                body["context"] = context
            }
        }

        return body
    }

    private func complete(_ result: Result<String, Error>) {
        guard !finished else { return }
        finished = true
        DispatchQueue.main.async { [weak self] in
            self?.onFinish?(result)
        }
    }

    private func consume(line: Data) {
        guard !line.isEmpty else { return }

        var payload = line
        // Tolerate SSE framing (`data: {...}`) as well as raw NDJSON.
        if let text = String(data: line, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != "[DONE]" else { return }
            if trimmed.hasPrefix("data:") {
                let stripped = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
                guard stripped != "[DONE]", let data = stripped.data(using: .utf8) else { return }
                payload = data
            }
        }

        guard let object = try? JSONSerialization.jsonObject(with: payload) else { return }
        handle(object)
    }

    private func handle(_ object: Any) {
        if let array = object as? [Any] {
            array.forEach(handle)
            return
        }

        guard let dictionary = object as? [String: Any] else { return }

        if let type = dictionary["type"] as? String {
            switch type {
            case "search", "tool-use", "tool_use", "notion-search":
                let label = dictionary["query"] as? String
                    ?? dictionary["name"] as? String
                    ?? "Searching your workspace"
                emitActivity(ActivityNote(symbol: "magnifyingglass", text: label))
            case "page", "read-page":
                let label = dictionary["title"] as? String ?? "Reading a page"
                emitActivity(ActivityNote(symbol: "doc.text", text: label))
            case "error":
                let message = dictionary["message"] as? String
                    ?? dictionary["error"] as? String
                    ?? "Notion AI returned an error."
                complete(.failure(NotionError.transport(message)))
                return
            default:
                break
            }
        }

        for key in ["markdown-chat", "markdownChat", "text", "delta", "content", "value", "completion"] {
            if let fragment = dictionary[key] as? String, !fragment.isEmpty {
                emitDelta(fragment)
                return
            }
            if let nested = dictionary[key] {
                if let nestedString = NotionAIStream.flatten(nested), !nestedString.isEmpty {
                    emitDelta(nestedString)
                    return
                }
            }
        }
    }

    /// Notion nests text as arrays of arrays; flatten anything string-like.
    private static func flatten(_ value: Any) -> String? {
        if let string = value as? String { return string }
        if let array = value as? [Any] {
            let parts = array.compactMap { flatten($0) }
            return parts.isEmpty ? nil : parts.joined()
        }
        if let dictionary = value as? [String: Any] {
            for key in ["text", "content", "value", "markdown-chat"] {
                if let nested = dictionary[key], let flat = flatten(nested) { return flat }
            }
        }
        return nil
    }

    private func emitDelta(_ fragment: String) {
        // Some revisions stream cumulative text, others stream increments.
        let increment: String
        if fragment.hasPrefix(accumulated), fragment.count >= accumulated.count, !accumulated.isEmpty {
            increment = String(fragment.dropFirst(accumulated.count))
            accumulated = fragment
        } else {
            increment = fragment
            accumulated += fragment
        }

        guard !increment.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onDelta?(increment)
        }
    }

    private func emitActivity(_ note: ActivityNote) {
        DispatchQueue.main.async { [weak self] in
            self?.onActivity?(note)
        }
    }
}

extension NotionAIStream: URLSessionDataDelegate {
    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300:
            completionHandler(.allow)
        case 401, 403:
            complete(.failure(NotionError.sessionExpired))
            completionHandler(.cancel)
        case 404:
            complete(.failure(NotionError.endpointUnavailable(AppSettings.shared.aiEndpointPath)))
            completionHandler(.cancel)
        default:
            complete(.failure(NotionError.http(status)))
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer.append(data)

        let newline = UInt8(ascii: "\n")
        while let index = buffer.firstIndex(of: newline) {
            let line = buffer.subdata(in: buffer.startIndex..<index)
            buffer.removeSubrange(buffer.startIndex...index)
            consume(line: line)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if !buffer.isEmpty {
            let remainder = buffer
            buffer = Data()
            consume(line: remainder)
        }

        if let error = error as NSError?, error.code == NSURLErrorCancelled {
            return
        }
        if let error = error {
            complete(.failure(NotionError.transport(error.localizedDescription)))
            return
        }

        if accumulated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            complete(.failure(NotionError.malformedResponse))
        } else {
            complete(.success(accumulated))
        }
    }
}
