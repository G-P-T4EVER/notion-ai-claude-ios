import Foundation

/// Streams an answer out of Notion AI.
///
/// The private endpoint changes shape between Notion releases, so this client
/// tries several known request shapes in order and parses anything that looks
/// like text: newline-delimited JSON, server-sent events or one JSON blob.
final class NotionAIStream: NSObject {
    struct Request {
        var messages: [ChatMessage]
        var mode: ChatMode
        var model: AIModel
        var effort: ModelEffort
        var conversationID: String
        var workspaceContext: String = ""
        var systemPrompt: String = ""
    }

    private struct Attempt {
        let path: String
        let body: [String: Any]
    }

    private var session: URLSession!
    private var task: URLSessionDataTask?

    private var buffer = Data()
    private var collected = ""
    private var rawLog = ""
    private var sawAnyText = false
    private var statusCode = 0

    private var attempts: [Attempt] = []
    private var attemptIndex = 0
    private var currentRequest: Request?

    private var onDelta: ((String) -> Void)?
    private var onActivity: ((ActivityNote) -> Void)?
    private var onProgress: ((String) -> Void)?
    private var onFinish: ((Result<String, Error>) -> Void)?

    private var progressTimer: Timer?
    private var progressStage = 0

    override init() {
        super.init()
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 300
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        configuration.httpShouldSetCookies = true
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    var isRunning: Bool { task != nil }

    // MARK: - Public API

    func start(
        _ request: Request,
        onDelta: @escaping (String) -> Void,
        onActivity: @escaping (ActivityNote) -> Void,
        onProgress: @escaping (String) -> Void,
        onFinish: @escaping (Result<String, Error>) -> Void
    ) {
        cancel()

        guard NotionSession.shared.isAuthenticated else {
            onFinish(.failure(NotionError.notAuthenticated))
            return
        }

        self.currentRequest = request
        self.onDelta = onDelta
        self.onActivity = onActivity
        self.onProgress = onProgress
        self.onFinish = onFinish

        collected = ""
        rawLog = ""
        sawAnyText = false
        attemptIndex = 0
        attempts = NotionAIStream.buildAttempts(for: request)

        startProgressTicker()
        runCurrentAttempt()
    }

    func cancel() {
        progressTimer?.invalidate()
        progressTimer = nil
        task?.cancel()
        task = nil
        buffer.removeAll()
    }

    // MARK: - Attempts

    private static func transcript(for request: Request) -> [[String: Any]] {
        var items: [[String: Any]] = []

        var preamble = request.systemPrompt
        if !request.workspaceContext.isEmpty {
            preamble += (preamble.isEmpty ? "" : "\n\n")
                + "Relevant pages in this workspace:\n" + request.workspaceContext
        }
        if !preamble.isEmpty {
            items.append(["type": "context", "value": preamble])
        }

        for message in request.messages where !message.text.isEmpty {
            switch message.role {
            case .user:
                items.append(["type": "human", "value": [[message.text]]])
            case .assistant:
                items.append(["type": "markdown-chat", "value": message.text])
            }
        }
        return items
    }

    private static func buildAttempts(for request: Request) -> [Attempt] {
        let spaceID = NotionSession.shared.spaceID ?? ""
        let traceID = UUID().uuidString
        let prompt = request.messages.last(where: { $0.role == .user })?.text ?? ""
        let configured = AppSettings.shared.aiEndpointPath

        var modelHints: [String: Any] = [
            "model": request.model.id,
            "effort": request.effort.rawValue,
            "mode": request.mode.rawValue
        ]
        if request.model.id == AIModel.auto.id {
            modelHints["model"] = "auto"
        }

        let transcriptBody: [String: Any] = [
            "spaceId": spaceID,
            "transcript": transcript(for: request),
            "createThread": false,
            "traceId": traceID,
            "threadId": request.conversationID,
            "generateTitle": false,
            "saveAllThreadOperations": false,
            "debugOverrides": [
                "cachedInferences": [:],
                "annotationInferences": [:],
                "emitInlineDebugInfo": false
            ],
            "metadata": modelHints
        ]

        let completionBody: [String: Any] = [
            "id": traceID,
            "spaceId": spaceID,
            "model": modelHints["model"] ?? request.model.id,
            "prompt": [
                "type": "chat",
                "text": prompt,
                "context": request.workspaceContext
            ],
            "context": [
                "mode": request.mode.rawValue,
                "effort": request.effort.rawValue
            ]
        ]

        let simpleBody: [String: Any] = [
            "spaceId": spaceID,
            "messages": request.messages.filter { !$0.text.isEmpty }.map {
                ["role": $0.role.rawValue, "content": $0.text]
            },
            "model": modelHints["model"] ?? request.model.id,
            "effort": request.effort.rawValue,
            "system": request.systemPrompt
        ]

        var paths: [String] = [configured]
        for fallback in ["runInferenceTranscript", "runInference", "getCompletion", "getAiChatCompletion"]
        where !paths.contains(fallback) {
            paths.append(fallback)
        }

        return paths.map { path -> Attempt in
            switch path {
            case "getCompletion":
                return Attempt(path: path, body: completionBody)
            case "getAiChatCompletion":
                return Attempt(path: path, body: simpleBody)
            default:
                return Attempt(path: path, body: transcriptBody)
            }
        }
    }

    private func runCurrentAttempt() {
        guard attemptIndex < attempts.count else {
            finish(.failure(diagnosticError()))
            return
        }

        let attempt = attempts[attemptIndex]
        buffer.removeAll()
        statusCode = 0

        do {
            var request = try NotionSession.shared.authorizedRequest(path: attempt.path, body: attempt.body)
            request.setValue("text/event-stream, application/x-ndjson, application/json",
                             forHTTPHeaderField: "Accept")
            AppSettings.shared.lastRequestInfo = "POST /api/v3/" + attempt.path
            let task = session.dataTask(with: request)
            self.task = task
            task.resume()
        } catch {
            finish(.failure(error))
        }
    }

    private func advanceOrFail() {
        attemptIndex += 1
        if attemptIndex < attempts.count {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.onActivity?(ActivityNote(symbol: "arrow.triangle.2.circlepath",
                                              text: "Retrying with another Notion AI endpoint"))
                self.runCurrentAttempt()
            }
        } else {
            finish(.failure(diagnosticError()))
        }
    }

    private func diagnosticError() -> Error {
        AppSettings.shared.lastRawResponse = rawLog
        if statusCode == 401 || statusCode == 403 { return NotionError.sessionExpired }
        if statusCode >= 400 { return NotionError.http(statusCode) }
        let hint = rawLog
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        if hint.isEmpty {
            return NotionError.endpointUnavailable(
                "Notion AI returned nothing. Check Settings → Capabilities → AI endpoint path."
            )
        }
        return NotionError.endpointUnavailable(String(hint.prefix(280)))
    }

    private func finish(_ result: Result<String, Error>) {
        progressTimer?.invalidate()
        progressTimer = nil
        task = nil
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let handler = self.onFinish
            self.onFinish = nil
            handler?(result)
        }
    }

    // MARK: - Progress

    private func startProgressTicker() {
        progressStage = 0
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.onProgress?(StreamingStatus.stage(at: 0))
            let timer = Timer.scheduledTimer(withTimeInterval: 1.6, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                guard !self.sawAnyText else { return }
                self.progressStage += 1
                self.onProgress?(StreamingStatus.stage(at: self.progressStage))
            }
            RunLoop.main.add(timer, forMode: .common)
            self.progressTimer = timer
        }
    }

    // MARK: - Parsing

    private func consume(_ data: Data) {
        buffer.append(data)

        while let range = buffer.firstRange(of: Data([0x0A])) {
            let lineData = buffer.subdata(in: 0..<range.lowerBound)
            buffer.removeSubrange(0..<range.upperBound)
            handleLine(String(data: lineData, encoding: .utf8) ?? "")
        }
    }

    private func flushBuffer() {
        guard !buffer.isEmpty else { return }
        let text = String(data: buffer, encoding: .utf8) ?? ""
        buffer.removeAll()
        handleLine(text)
    }

    private func handleLine(_ rawLine: String) {
        var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }

        if rawLog.count < 8_000 {
            rawLog += line + "\n"
        }

        if line.hasPrefix("event:") || line.hasPrefix(":") { return }
        if line.hasPrefix("data:") {
            line = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        }
        if line == "[DONE]" || line == "DONE" { return }

        guard let data = line.data(using: .utf8) else { return }

        if let json = try? JSONSerialization.jsonObject(with: data) {
            var pieces: [String] = []
            var notes: [ActivityNote] = []
            NotionAIStream.extract(from: json, text: &pieces, notes: &notes)
            for note in notes { emit(note: note) }
            for piece in pieces where !piece.isEmpty { emit(text: piece) }
            return
        }

        // Not JSON: some deployments stream plain text chunks.
        if !line.hasPrefix("{") && !line.hasPrefix("[") {
            emit(text: line)
        }
    }

    /// Recursively pulls text out of any response shape.
    private static func extract(from json: Any, text: inout [String], notes: inout [ActivityNote], depth: Int = 0) {
        guard depth < 8 else { return }

        if let dict = json as? [String: Any] {
            let type = (dict["type"] as? String) ?? ""

            if type == "markdown-chat" || type == "markdown" || type == "text" || type == "chat" {
                if let value = dict["value"] as? String { text.append(value) }
                if let value = dict["text"] as? String { text.append(value) }
                if let value = dict["content"] as? String { text.append(value) }
            }

            if type.contains("search") || type.contains("tool") || type.contains("retrieval") {
                notes.append(ActivityNote(symbol: "magnifyingglass", text: "Searching your workspace"))
            }
            if type.contains("page") && type.contains("read") {
                notes.append(ActivityNote(symbol: "doc.text", text: "Reading a page"))
            }

            for key in ["completion", "delta", "chunk", "markdown", "output_text"] {
                if let value = dict[key] as? String, !value.isEmpty { text.append(value) }
            }

            if type.isEmpty, let value = dict["value"] as? String, dict["id"] == nil, !value.isEmpty {
                text.append(value)
            }

            if let message = dict["message"] as? [String: Any] {
                extract(from: message, text: &text, notes: &notes, depth: depth + 1)
            }
            if let content = dict["content"] as? [Any] {
                for item in content {
                    extract(from: item, text: &text, notes: &notes, depth: depth + 1)
                }
            }
            for key in ["choices", "results", "events", "items", "data", "parts", "value", "transcript"] {
                if let nested = dict[key], !(nested is String) {
                    extract(from: nested, text: &text, notes: &notes, depth: depth + 1)
                }
            }
            if let error = dict["errorId"] as? String {
                notes.append(ActivityNote(symbol: "exclamationmark.triangle", text: "Notion error \(error)"))
            }
        } else if let array = json as? [Any] {
            for element in array {
                if let string = element as? String, array.count == 1, !string.isEmpty {
                    text.append(string)
                } else {
                    extract(from: element, text: &text, notes: &notes, depth: depth + 1)
                }
            }
        }
    }

    private func emit(text piece: String) {
        guard !piece.isEmpty else { return }

        // Some endpoints send the full answer each tick instead of a delta.
        var delta = piece
        if piece.hasPrefix(collected), piece.count > collected.count, !collected.isEmpty {
            delta = String(piece.dropFirst(collected.count))
            collected = piece
        } else {
            collected += piece
        }

        if !sawAnyText {
            sawAnyText = true
            DispatchQueue.main.async {
                Feedback.streamStart()
            }
        }

        DispatchQueue.main.async { [weak self] in
            self?.onDelta?(delta)
        }
    }

    private func emit(note: ActivityNote) {
        DispatchQueue.main.async { [weak self] in
            self?.onActivity?(note)
            self?.onProgress?(note.text + "…")
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
        statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        if statusCode >= 400 {
            // Read the error body so diagnostics can show it, then move on.
            completionHandler(.allow)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if statusCode >= 400 {
            if rawLog.count < 8_000, let text = String(data: data, encoding: .utf8) {
                rawLog += text
            }
            return
        }
        consume(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error as NSError?, error.code == NSURLErrorCancelled {
            self.task = nil
            return
        }

        if let error = error {
            AppSettings.shared.lastRawResponse = rawLog
            if sawAnyText {
                finish(.success(collected))
            } else if attemptIndex + 1 < attempts.count {
                advanceOrFail()
            } else {
                finish(.failure(NotionError.transport(error.localizedDescription)))
            }
            return
        }

        flushBuffer()
        AppSettings.shared.lastRawResponse = rawLog

        if sawAnyText, !collected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            finish(.success(collected))
        } else {
            advanceOrFail()
        }
    }
}

private extension Data {
    func firstRange(of separator: Data) -> Range<Int>? {
        guard !separator.isEmpty, count >= separator.count else { return nil }
        let bytes = [UInt8](self)
        let target = [UInt8](separator)
        var index = 0
        while index <= bytes.count - target.count {
            if Array(bytes[index..<(index + target.count)]) == target {
                return index..<(index + target.count)
            }
            index += 1
        }
        return nil
    }
}
