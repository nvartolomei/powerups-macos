import Cocoa
import Quartz
import WebKit

/// Quick Look preview for Markdown documents. Renders GFM in an isolated,
/// network-less WKWebView: JavaScript runs (remark needs it) but there is no
/// inbound script-message handler and the page CSP forbids the network, so a
/// hostile document can neither reach AppKit nor phone home. The document is
/// injected as a global before load via a document-start user script, and the
/// page renders itself (falling back to plain text on any failure).
class PreviewViewController: NSViewController, QLPreviewingController {
    private static let maxBytes = 5 * 1024 * 1024
    private static let openURLNotification = Notification.Name("com.nvartolomei.powerups.quicklook-markdown.openURL")
    private var webView: WKWebView!
    private var completion: ((Error?) -> Void)?

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        webView = makeWebView()
        view.addSubview(webView)
    }

    private func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: view.bounds, configuration: configuration)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        return webView
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        guard let template = Bundle.main.url(forResource: "preview", withExtension: "html") else {
            handler(PreviewError.templateMissing)
            return
        }
        completion = handler
        injectMarkdown(readMarkdown(at: url))
        webView.loadFileURL(template, allowingReadAccessTo: template.deletingLastPathComponent())
    }

    /// The extension is sandboxed and cannot open URLs (lsopen denied), so it
    /// hands the clicked link to the unsandboxed PowerUps app, which opens it.
    private func postOpenURL(_ url: URL) {
        DistributedNotificationCenter.default().postNotificationName(Self.openURLNotification, object: url.absoluteString, userInfo: nil, deliverImmediately: true)
    }

    private func injectMarkdown(_ markdown: String) {
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        let source = "window.__markdown__ = \(jsStringLiteral(markdown));"
        controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }

    private func jsStringLiteral(_ string: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: string, options: [.fragmentsAllowed]),
              let json = String(data: data, encoding: .utf8) else { return "\"\"" }
        return json
    }

    private func readMarkdown(at url: URL) -> String {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return "" }
        let bytes = data.count > Self.maxBytes ? data.prefix(Self.maxBytes) : data
        return String(decoding: bytes, as: UTF8.self)
    }

    private func finish(_ error: Error?) {
        completion?(error)
        completion = nil
    }

    enum PreviewError: Error { case templateMissing }
}

extension PreviewViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish(nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(error)
    }

    /// Only the initial local template load is allowed inside the view; link
    /// clicks open in the default browser, everything else is refused.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        if navigationAction.navigationType == .other, url.isFileURL {
            decisionHandler(.allow)
            return
        }
        if navigationAction.navigationType == .linkActivated {
            postOpenURL(url)
        }
        decisionHandler(.cancel)
    }
}
