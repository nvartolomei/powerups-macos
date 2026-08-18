import Cocoa

struct ChatMessage {
    enum Role: String {
        case user
        case assistant
    }

    let role: Role
    var text: String
}

/// one conversation, owned by one window. the endpoint and model are captured when the session starts, so changing
/// the settings mid-conversation doesn't switch models halfway through an exchange
class ChatSession {
    let model: String
    private let endpoint: String
    private let format: LLMFormatPreference
    private let webSearch: Bool
    private(set) var messages = [ChatMessage]()
    private var client: LLMClient?
    var isStreaming: Bool { client != nil }

    init() {
        endpoint = Preferences.llmEndpoint
        model = Preferences.llmModel
        format = Preferences.llmFormat
        webSearch = Preferences.llmWebSearch && format.supportsWebSearch
    }

    /// `handler` receives `.text` on the network queue and everything else on the main queue
    func send(_ prompt: String, _ handler: @escaping (LLMEvent) -> Void) {
        // read at send time, so a key added in the settings applies to a window that is already open
        guard let apiKey = LLMKeychain.apiKey() else {
            handler(.failed(NSLocalizedString("No API key yet. Add one in Settings → AI.", comment: "")))
            return
        }
        messages.append(ChatMessage(role: .user, text: prompt))
        Logger.info { "\(self.model) \(self.messages.count) messages" }
        let client = LLMClient()
        self.client = client
        let configuration = LLMConfiguration(endpoint: endpoint, model: model, format: format,
                                             webSearch: webSearch, apiKey: apiKey)
        client.send(messages, configuration) { [weak self] event in
            switch event {
                // a text delta arrives on the network queue, so nothing on the session may be touched for it
                case .text: break
                default: self?.record(event)
            }
            handler(event)
        }
    }

    func cancel() {
        client?.cancel()
    }

    /// the transcript as markdown, which is what makes it useful to paste anywhere else
    func transcript() -> String {
        messages.map { "**\($0.role == .user ? "You" : "Assistant")**\n\n\($0.text)" }.joined(separator: "\n\n")
    }

    private func record(_ event: LLMEvent) {
        switch event {
            case .finished(let answer):
                client = nil
                guard !answer.isEmpty else { return }
                messages.append(ChatMessage(role: .assistant, text: answer))
            case .failed:
                client = nil
                // the failed exchange stays out of the history, so a retry doesn't resend a dangling user turn
                if messages.last?.role == .user {
                    messages.removeLast()
                }
            default: break
        }
    }
}
