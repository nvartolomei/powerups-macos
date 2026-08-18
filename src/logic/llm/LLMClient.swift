import Cocoa

struct LLMConfiguration {
    let endpoint: String
    let model: String
    let format: LLMFormatPreference
    let webSearch: Bool
    let apiKey: String
}

enum LLMEvent {
    /// a line of the model's summarized reasoning, to show while the answer hasn't started
    case status(String)
    /// an answer fragment; delivered on the parsing queue so the UI can buffer it off the main thread
    case text(String)
    /// the whole answer, on the main queue, once the response ends (including when it was stopped early)
    case finished(String)
    case failed(String)
}

/// streams one answer over server-sent events, then is done: a client is single-use, so no request can observe
/// leftovers from the previous one
class LLMClient: NSObject {
    static let defaultEndpoint = "https://api.anthropic.com"
    static let defaultModel = "claude-opus-5"
    /// the answer shares the token budget with the model's reasoning, so this is not the length of the answer itself
    private static let maxTokens = 16000
    private static let systemPrompt = """
        You answer quick questions in a small always-on-top window, next to whatever the user is already doing.
        Lead with the answer in the first sentence, then only the detail that changes what the reader does next.
        Skip preamble, restatements of the question, and caveats that don't apply to it.
        """
    private static let dataPrefix = Data("data:".utf8)
    /// the sentinel that ends a chat-completions or responses stream
    private static let doneSentinel = Data("[DONE]".utf8)
    /// decided in `send`; the stream can't be read without knowing which shape produced it
    private var format = LLMFormatPreference.messages
    private var task: URLSessionDataTask?
    private var handler: ((LLMEvent) -> Void)?
    /// bytes received but not yet terminated by a newline
    private var pendingBytes = Data()
    private var answer = ""
    /// the tail of the reasoning summary that hasn't been terminated by a newline yet
    private var partialStatusLine = ""
    private var hasEmittedStatus = false
    /// why the model stopped, when it stopped for a reason the window has to explain
    private var stopReason: String?
    private var isFinished = false
    /// set when the response status isn't 2xx, in which case the body is an error payload rather than a stream
    private var errorStatus: Int?
    private var errorBody = Data()

    func send(_ messages: [ChatMessage], _ configuration: LLMConfiguration, _ handler: @escaping (LLMEvent) -> Void) {
        format = configuration.format
        self.handler = handler
        guard let request = makeRequest(messages, configuration) else {
            finish(NSLocalizedString("The endpoint in the settings isn't a valid URL.", comment: ""))
            return
        }
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        // a slow first token is normal; the resource timeout is what bounds a stalled answer
        sessionConfiguration.timeoutIntervalForRequest = 120
        sessionConfiguration.timeoutIntervalForResource = 900
        // a stream is read once and never re-read, so the default in-memory response cache is pure overhead
        sessionConfiguration.urlCache = nil
        let session = URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: nil)
        task = session.dataTask(with: request)
        task!.resume()
    }

    func cancel() {
        task?.cancel()
    }

    private func makeRequest(_ messages: [ChatMessage], _ configuration: LLMConfiguration) -> URLRequest? {
        let base = Self.normalized(configuration.endpoint)
        guard let url = URL(string: base + path(configuration.format)) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("text/event-stream", forHTTPHeaderField: "accept")
        let body: [String: Any]
        switch configuration.format {
            case .messages:
                request.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
                request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                // a request the model declines is re-run server-side on the recommended alternative, which only
                // the endpoint this shape was designed for knows how to do
                let usesFallbacks = base.caseInsensitiveCompare(Self.defaultEndpoint) == .orderedSame
                if usesFallbacks {
                    request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
                }
                body = messagesBody(messages, configuration, usesFallbacks)
            case .chatCompletions:
                request.setValue("Bearer " + configuration.apiKey, forHTTPHeaderField: "authorization")
                body = chatCompletionsBody(messages, configuration)
            case .responses:
                request.setValue("Bearer " + configuration.apiKey, forHTTPHeaderField: "authorization")
                body = responsesBody(messages, configuration)
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request.httpBody == nil ? nil : request
    }

    private func path(_ format: LLMFormatPreference) -> String {
        switch format {
            case .messages: return "/v1/messages"
            case .chatCompletions: return "/v1/chat/completions"
            case .responses: return "/v1/responses"
        }
    }

    private func messagesBody(_ messages: [ChatMessage], _ configuration: LLMConfiguration, _ usesFallbacks: Bool) -> [String: Any] {
        var body: [String: Any] = [
            "model": configuration.model,
            "max_tokens": Self.maxTokens,
            "stream": true,
            "system": Self.systemPrompt,
            // a quick question wants the answer now; this trades reasoning depth for latency
            "output_config": ["effort": "low"],
            // the summary gives the window something truthful to show before the first answer token
            "thinking": ["type": "adaptive", "display": "summarized"],
            "messages": wireMessages(messages),
        ]
        if configuration.webSearch {
            // run by the server, so there is no tool loop on this side. web fetch only reads URLs that are already
            // in the conversation, which is what makes a pasted link answerable
            body["tools"] = [
                ["type": "web_search_20260209", "name": "web_search"],
                ["type": "web_fetch_20260209", "name": "web_fetch"],
            ]
        }
        if usesFallbacks {
            body["fallbacks"] = "default"
        }
        return body
    }

    /// no token ceiling is sent: the field for it was renamed on newer models and the old name is rejected there,
    /// while servers that only speak the older shape reject the new one. the system prompt is what keeps answers short
    private func chatCompletionsBody(_ messages: [ChatMessage], _ configuration: LLMConfiguration) -> [String: Any] {
        [
            "model": configuration.model,
            "stream": true,
            "messages": wireMessages(messages, withSystemPrompt: true),
        ]
    }

    /// the system prompt goes in as the first input message rather than in `instructions`, which keeps the request
    /// valid on any server that implements the message list. no token ceiling, for the same reason as above
    private func responsesBody(_ messages: [ChatMessage], _ configuration: LLMConfiguration) -> [String: Any] {
        var body: [String: Any] = [
            "model": configuration.model,
            "stream": true,
            "input": wireMessages(messages, withSystemPrompt: true),
        ]
        if configuration.webSearch {
            // the model decides whether to search; the loop runs server-side
            body["tools"] = [["type": "web_search"]]
        }
        return body
    }

    private func wireMessages(_ messages: [ChatMessage], withSystemPrompt: Bool = false) -> [[String: String]] {
        let system = withSystemPrompt ? [["role": "system", "content": Self.systemPrompt]] : []
        return system + messages.map { ["role": $0.role.rawValue, "content": $0.text] }
    }

    private static func normalized(_ endpoint: String) -> String {
        var trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        return trimmed
    }

    private func consume(_ line: Data.SubSequence) {
        guard line.starts(with: Self.dataPrefix) else { return }
        let payload = line.dropFirst(Self.dataPrefix.count).drop { $0 == 0x20 }
        if payload.elementsEqual(Self.doneSentinel) {
            finish(nil)
            return
        }
        guard let event = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] else { return }
        switch format {
            case .messages: handleMessagesEvent(event)
            case .chatCompletions: handleChatCompletionsEvent(event)
            case .responses: handleResponsesEvent(event)
        }
    }

    private func handleMessagesEvent(_ event: [String: Any]) {
        switch event["type"] as? String {
            case "content_block_delta":
                guard let delta = event["delta"] as? [String: Any] else { return }
                if let text = delta["text"] as? String, !text.isEmpty {
                    appendAnswer(text)
                } else if let thinking = delta["thinking"] as? String, !thinking.isEmpty {
                    appendStatus(thinking)
                }
            case "content_block_start":
                guard let block = event["content_block"] as? [String: Any],
                      block["type"] as? String == "server_tool_use" else { return }
                emitStatus(block["name"] as? String == "web_fetch"
                    ? NSLocalizedString("Reading the page…", comment: "")
                    : NSLocalizedString("Searching the web…", comment: ""))
            case "message_delta":
                // "pause_turn" means the turn ran the search tool to its iteration limit and expects to be continued
                stopReason = (event["delta"] as? [String: Any])?["stop_reason"] as? String
            case "message_stop":
                finish(nil)
            case "error":
                finish((event["error"] as? [String: Any])?["message"] as? String)
            default: break
        }
    }

    /// the stream ends with a `[DONE]` sentinel rather than a typed event, so `finish_reason` is only informational
    private func handleChatCompletionsEvent(_ event: [String: Any]) {
        guard let delta = (event["choices"] as? [[String: Any]])?.first?["delta"] as? [String: Any] else {
            // some servers report a mid-stream failure in the stream rather than through the response status
            if let message = (event["error"] as? [String: Any])?["message"] as? String {
                finish(message)
            }
            return
        }
        if let text = delta["content"] as? String, !text.isEmpty {
            appendAnswer(text)
        } else if let reasoning = delta["reasoning_content"] as? String, !reasoning.isEmpty {
            appendStatus(reasoning)
        }
    }

    /// typed events rather than one delta shape: text, reasoning summary, and the search tool each have their own
    private func handleResponsesEvent(_ event: [String: Any]) {
        switch event["type"] as? String {
            case "response.output_text.delta":
                if let text = event["delta"] as? String, !text.isEmpty { appendAnswer(text) }
            case "response.reasoning_summary_text.delta":
                if let summary = event["delta"] as? String, !summary.isEmpty { appendStatus(summary) }
            case "response.web_search_call.in_progress", "response.web_search_call.searching":
                emitStatus(NSLocalizedString("Searching the web…", comment: ""))
            case "response.completed":
                finish(nil)
            case "response.failed", "response.incomplete":
                let response = event["response"] as? [String: Any]
                finish((response?["error"] as? [String: Any])?["message"] as? String)
            case "error":
                finish(event["message"] as? String ?? (event["error"] as? [String: Any])?["message"] as? String)
            default: break
        }
    }

    private func appendAnswer(_ text: String) {
        answer += text
        handler?(.text(text))
    }

    /// the status line is one line of the summary at a time: enough to show progress, without a main-thread hop
    /// per token. the very first fragment is shown as-is, so something appears as soon as the model starts
    private func appendStatus(_ thinking: String) {
        partialStatusLine += thinking
        if thinking.contains("\n") {
            let lines = partialStatusLine.components(separatedBy: "\n")
            partialStatusLine = lines.last ?? ""
            if let completed = lines.dropLast().last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                emitStatus(completed)
                return
            }
        }
        guard !hasEmittedStatus else { return }
        emitStatus(partialStatusLine)
    }

    private func emitStatus(_ line: String) {
        let cleaned = line.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return }
        hasEmittedStatus = true
        emitOnMain(.status(cleaned))
    }

    private func finish(_ error: String?) {
        guard !isFinished else { return }
        isFinished = true
        if let error {
            emitOnMain(.failed(error))
        } else if !answer.isEmpty {
            // whatever was written stands on its own, whichever way the turn ended
            emitOnMain(.finished(answer))
        } else if stopReason == "refusal" {
            emitOnMain(.failed(NSLocalizedString("The model declined to answer this.", comment: "")))
        } else if stopReason == "pause_turn" {
            Logger.error { "the turn paused mid-search with nothing written" }
            emitOnMain(.failed(NSLocalizedString("The search didn't finish. Ask again.", comment: "")))
        } else {
            emitOnMain(.finished(answer))
        }
        handler = nil
    }

    private func emitOnMain(_ event: LLMEvent) {
        guard let handler else { return }
        DispatchQueue.main.async { handler(event) }
    }

    private func errorMessage(_ status: Int) -> String {
        if let payload = (try? JSONSerialization.jsonObject(with: errorBody)) as? [String: Any],
           let message = (payload["error"] as? [String: Any])?["message"] as? String, !message.isEmpty {
            return message
        }
        if status == 401 || status == 403 {
            return NSLocalizedString("The API key was rejected. Check it in Settings → AI.", comment: "")
        }
        if status == 404 {
            return NSLocalizedString("The endpoint has no such path. Check the API format in Settings → AI.", comment: "")
        }
        return String(format: NSLocalizedString("The request failed (HTTP %d).", comment: ""), status)
    }
}

extension LLMClient: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            errorStatus = http.statusCode
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard errorStatus == nil else {
            errorBody.append(data)
            return
        }
        pendingBytes.append(data)
        // one trailing removal per chunk rather than one per line: a stream is three lines per token
        var scan = pendingBytes.startIndex
        while let newline = pendingBytes[scan...].firstIndex(of: 0x0A) {
            // servers may terminate with CRLF; ending the slice short of it keeps the parse free of copies
            let end = newline > scan && pendingBytes[newline - 1] == 0x0D ? newline - 1 : newline
            consume(pendingBytes[scan..<end])
            scan = pendingBytes.index(after: newline)
        }
        pendingBytes.removeSubrange(pendingBytes.startIndex..<scan)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        session.finishTasksAndInvalidate()
        if let status = errorStatus {
            finish(errorMessage(status))
        } else if (error as? URLError)?.code == .cancelled {
            // stopped from the window; whatever arrived stays in the transcript
            finish(nil)
        } else if let error {
            finish(error.localizedDescription)
        } else {
            finish(nil)
        }
    }
}
