import Cocoa

/// the scrolled list of messages. it lays its messages out top-down and sizes itself to them, so the scroll view
/// has a document height to work with
class ChatTranscriptView: FlippedView {
    private static let spacing = CGFloat(12)
    private var messageViews = [ChatMessageView]()
    var onLaidOut: (() -> Void)?

    func append(_ messageView: ChatMessageView) {
        messageViews.append(messageView)
        addSubview(messageView)
        needsLayout = true
    }

    func remove(_ messageView: ChatMessageView) {
        guard let index = messageViews.firstIndex(of: messageView) else { return }
        messageViews.remove(at: index)
        messageView.removeFromSuperview()
        needsLayout = true
    }

    func teardown() {
        messageViews.forEach { $0.stopRendering() }
    }

    override func layout() {
        super.layout()
        let width = max(1, superview?.bounds.width ?? bounds.width)
        var y = CGFloat(0)
        for messageView in messageViews {
            let size = messageView.layoutContent(width)
            // what the user sent hugs the right edge, the answer uses the full width
            let x = messageView.role == .user ? width - size.width : 0
            messageView.frame = NSRect(x: x, y: y, width: size.width, height: size.height)
            y += size.height + Self.spacing
        }
        let height = max(0, y - Self.spacing)
        if abs(frame.height - height) > 0.5 || abs(frame.width - width) > 0.5 {
            frame = NSRect(x: 0, y: 0, width: width, height: height)
        }
        onLaidOut?()
    }
}

/// an unflipped clip view would stack the transcript from the bottom of the scroll view
class ChatClipView: NSClipView {
    override var isFlipped: Bool { true }
}
