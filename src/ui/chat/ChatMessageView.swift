import Cocoa
import QuartzCore

/// one message in the transcript, and the target the answer streams into.
///
/// deltas arrive on the network queue and are appended to a buffer; a display link splices the buffer into the text
/// storage once per frame, so rendering runs at the display's rate instead of the token rate. if a splice overruns
/// the frame budget the next callback simply comes later and the bigger buffer is spliced in one go, which is the
/// back pressure a fixed-interval timer doesn't give us. an idle message costs no callbacks at all.
class ChatMessageView: NSView {
    private static let bubblePadding = NSSize(width: 12, height: 8)
    private static let plainPadding = NSSize(width: 2, height: 7)
    private static let maxUserWidthRatio = CGFloat(0.85)
    let role: ChatMessage.Role
    private let textStorage: NSTextStorage
    private let layoutManager: NSLayoutManager
    private let textContainer: NSTextContainer
    private let textView: ChatTextView
    private var renderLink: CADisplayLink?
    /// guards the two fields below, which the network queue writes and the display link reads
    private let pendingLock = NSLock()
    private var pending = ""
    private var isRenderLinkRunning = false
    private(set) var text = ""
    private var padding: NSSize { role == .user ? Self.bubblePadding : Self.plainPadding }
    var onContentChanged: (() -> Void)?
    var onTypedInto: ((NSEvent) -> Void)?

    init(_ role: ChatMessage.Role) {
        self.role = role
        let storage = NSTextStorage()
        let manager = ChatLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        textStorage = storage
        layoutManager = manager
        textContainer = container
        // building the TextKit stack by hand keeps the message on TextKit 1, whose usedRect gives us an exact
        // height to lay out with, and whose incremental layout only touches the tail we appended
        textView = ChatTextView(frame: .zero, textContainer: container)
        super.init(frame: .zero)
        configureTextView()
        wantsLayer = true
        layer!.cornerRadius = 14
        layer!.cornerCurve = .continuous
        layer!.backgroundColor = role == .user ? Appearance.highlightFocusedBackgroundColor.cgColor : NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    /// what the user typed is shown verbatim: a question about markdown shouldn't be rendered as markdown
    func setText(_ value: String) {
        text = value
        textStorage.setAttributedString(role == .user ? ChatMarkdown.plain(value) : ChatMarkdown.render(value))
        onContentChanged?()
    }

    /// called on the network queue
    func appendStreamedText(_ delta: String) {
        pendingLock.lock()
        pending += delta
        let needsWake = !isRenderLinkRunning
        isRenderLinkRunning = true
        pendingLock.unlock()
        guard needsWake else { return }
        DispatchQueue.main.async { [weak self] in self?.renderLink?.isPaused = false }
    }

    func endStreaming(_ finalText: String) {
        pendingLock.lock()
        pending = ""
        isRenderLinkRunning = false
        pendingLock.unlock()
        renderLink?.isPaused = true
        setText(finalText)
    }

    /// a display link retains its target, so the window has to drop it explicitly or the message outlives the window
    func stopRendering() {
        renderLink?.invalidate()
        renderLink = nil
    }

    /// lays the message out within `maxWidth` and reports the size it needs; a user message hugs its text
    func layoutContent(_ maxWidth: CGFloat) -> NSSize {
        let widthLimit = role == .user ? (maxWidth * Self.maxUserWidthRatio).rounded() : maxWidth
        let availableWidth = max(1, widthLimit - padding.width * 2)
        textContainer.size = NSSize(width: availableWidth, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer)
        let textWidth = role == .user ? min(ceil(widthInUse()), availableWidth) : availableWidth
        let textHeight = ceil(used.height)
        let size = NSSize(width: textWidth + padding.width * 2, height: textHeight + padding.height * 2)
        textView.frame = NSRect(origin: .zero, size: size)
        return size
    }

    /// how wide the text really is. `usedRect` reports the container's own width instead, from the first time the
    /// container is resized onwards, which would grow a bubble to the maximum on every resize and never shrink it
    private func widthInUse() -> CGFloat {
        var width = CGFloat(0)
        layoutManager.enumerateLineFragments(forGlyphRange: layoutManager.glyphRange(for: textContainer)) { _, used, _, _, _ in
            width = max(width, used.maxX)
        }
        return width
    }

    func copyToClipboard() {
        Logger.info { "\(self.role.rawValue) \(self.text.count) characters" }
        NSPasteboard.copy(text)
    }

    /// the link is bound to the display the window is on, so it follows a variable refresh rate on its own
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            stopRendering()
            return
        }
        guard renderLink == nil else { return }
        let link = displayLink(target: self, selector: #selector(renderPendingText))
        link.add(to: .main, forMode: .common)
        link.isPaused = true
        renderLink = link
    }

    /// draining, the emptiness check, and pausing all happen under the lock, so a delta that lands between the
    /// drain and the pause always finds `isRenderLinkRunning` false and schedules a wake
    @objc private func renderPendingText() {
        pendingLock.lock()
        let batch = pending
        pending = ""
        if batch.isEmpty {
            isRenderLinkRunning = false
            pendingLock.unlock()
            renderLink?.isPaused = true
            return
        }
        pendingLock.unlock()
        text += batch
        // markdown is rendered once the answer completes: re-parsing the whole answer per frame would be quadratic
        textStorage.append(ChatMarkdown.plain(batch))
        onContentChanged?()
    }

    private func configureTextView() {
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = padding
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.onTypingKey = { [weak self] event in self?.onTypedInto?(event) }
        textView.onCopyMessage = { [weak self] in self?.copyToClipboard() }
        addSubview(textView)
    }
}

/// the transcript is selectable, so clicking a message parks the keyboard focus in it. typing has to land back in
/// the composer, and the contextual menu should offer the whole message and not only what is selected
class ChatTextView: NSTextView {
    var onTypingKey: ((NSEvent) -> Void)?
    var onCopyMessage: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        let isShortcut = event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control)
        guard !isShortcut, !(event.charactersIgnoringModifiers ?? "").isEmpty, let onTypingKey else {
            super.keyDown(with: event)
            return
        }
        onTypingKey(event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        let item = NSMenuItem(title: NSLocalizedString("Copy Message", comment: ""), action: #selector(copyMessage), keyEquivalent: "")
        item.target = self
        menu.insertItem(item, at: 0)
        menu.insertItem(NSMenuItem.separator(), at: 1)
        return menu
    }

    @objc private func copyMessage() {
        onCopyMessage?()
    }
}
