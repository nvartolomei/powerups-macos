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

class ChatTranscriptFadeView: NSView {
    private static let fadeHeight = CGFloat(32)
    private let fade = noAnimation { CAGradientLayer() }
    private let scrollView: NSScrollView
    private var fadedHeight = CGFloat(0)

    init(_ scrollView: NSScrollView) {
        self.scrollView = scrollView
        super.init(frame: .zero)
        wantsLayer = true
        fade.colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        fade.startPoint = CGPoint(x: 0.5, y: 1)
        fade.endPoint = CGPoint(x: 0.5, y: 0)
        addSubview(scrollView)
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        updateFade()
    }

    func updateFade() {
        let height = fadeHeight()
        guard height != fadedHeight || (height > 0 && fade.frame.size != bounds.size) else { return }
        fadedHeight = height
        guard height > 0 else { layer!.mask = nil; return }
        fade.frame = CGRect(origin: .zero, size: bounds.size)
        fade.locations = [0, NSNumber(value: Double(1 - height / bounds.height)), 1]
        layer!.mask = fade
    }

    private func fadeHeight() -> CGFloat {
        guard bounds.height > 0, let documentView = scrollView.documentView else { return 0 }
        return min(max(0, documentView.bounds.height - scrollView.contentView.bounds.maxY), Self.fadeHeight)
    }
}
