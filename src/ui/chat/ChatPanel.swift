import Cocoa

/// a conversation window. every question from the launcher opens its own, and they float above other apps without
/// pulling focus back when you return to what you were doing
class ChatPanel: NSPanel {
    private static var panels = [ChatPanel]()
    private static let defaultSize = NSSize(width: 470, height: 430)
    private static let padding = CGFloat(12)
    private static let rowSpacing = CGFloat(6)
    private static let sendButtonSize = CGFloat(24)
    private static let statusHeight = CGFloat(16)
    private static let composerInset = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
    private static let cascadeStep = CGFloat(26)
    private static let cascadeCount = CGFloat(6)
    private static let sendImage = NSImage.templateSymbol("arrow.up.circle.fill", 17)
    private static let stopImage = NSImage.templateSymbol("stop.circle.fill", 17)
    private static let copyImage = NSImage.templateSymbol("doc.on.doc", 13)
    private static let copyButtonSize = NSSize(width: 24, height: 20)
    private static let buttonMargin = CGFloat(2)
    private static let titlebarInset = CGFloat(9)
    private static let titlebarAccessoryWidth = copyButtonSize.width + titlebarInset
    private static let titleFont = NSFont.titleBarFont(ofSize: NSFont.systemFontSize)
    /// measured on macOS 26: the title starts 13pt past the zoom button. the trailing gap is the clear space the
    /// ellipsis leaves before the copy button
    private static let titleLeadingGap = CGFloat(13)
    private static let titleTrailingGap = CGFloat(8)
    private static let ellipsis = "…"
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    private let session = ChatSession()
    private let glassView = LiquidGlassEffectView(nil)
    private let content = ChatContentView()
    private let scrollView = NSScrollView()
    private lazy var transcriptFade = ChatTranscriptFadeView(scrollView)
    private let transcriptView = ChatTranscriptView()
    private let composer = ChatComposerView()
    private let composerScrollView = ChatComposerScrollView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()
    private let sendButton = NSButton()
    private weak var answerView: ChatMessageView?
    /// the title as it would read in full; what the titlebar shows is this cut down to the width it has
    private var fullTitle = ""
    /// the width the shown title was last cut to fit, so a resize that leaves it unchanged re-measures nothing
    private var titleFittedWidth: CGFloat?
    /// the transcript follows new text only while the reader hasn't scrolled up to look at something
    private var stickToBottom = true
    /// what the send button is currently showing, which leads the session: an exchange is set up before it starts
    private var isStreaming = false

    static func start(_ prompt: String) {
        let panel = ChatPanel()
        panels.append(panel)
        panel.show()
        panel.submit(prompt)
    }

    convenience init() {
        self.init(contentRect: NSRect(origin: .zero, size: Self.defaultSize),
                  styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                  backing: .buffered, defer: false)
        delegate = self
        isFloatingPanel = true
        level = .floating
        // staying up while another app is in front is the point of the window; it's a reference, not a destination
        hidesOnDeactivate = false
        collectionBehavior = [.fullScreenAuxiliary]
        isReleasedWhenClosed = false
        updateTitle(NSLocalizedString("Ask AI", comment: ""))
        minSize = NSSize(width: 340, height: 260)
        configureTranscript()
        configureComposer()
        configureStatus()
        configureTitlebarAccessory()
        configureGlass()
        configureContent()
    }

    private func configureGlass() {
        titlebarAppearsTransparent = true
        titlebarSeparatorStyle = .none
        isOpaque = false
        backgroundColor = .clear
        glassView.cornerRadius = 0
    }

    private func configureContent() {
        content.onLayout = { [weak self] in self?.layoutContents() }
        content.setSubviews([transcriptFade, spinner, statusLabel, composerScrollView, sendButton])
        content.autoresizingMask = [.width, .height]
        glassView.setContent(content)
        contentView = glassView
    }

    @objc func copyTranscript() {
        let transcript = session.transcript()
        Logger.info { "\(transcript.count) characters" }
        guard !transcript.isEmpty else { return }
        NSPasteboard.copy(transcript)
    }

    private func show() {
        NSScreen.updatePreferred()
        positionOnPreferredScreen()
        App.shared.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        makeFirstResponder(composer)
    }

    private func submit(_ prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !session.isStreaming else { return }
        if session.messages.isEmpty {
            updateTitle(String(trimmed.prefix(60)))
        }
        // setting `string` doesn't go through didChangeText, so the composer has to be re-measured by hand
        composer.string = ""
        content.needsLayout = true
        appendMessage(.user).setText(trimmed)
        let answerView = appendMessage(.assistant)
        self.answerView = answerView
        setStreaming(true)
        setStatus(NSLocalizedString("Thinking…", comment: ""), isError: false)
        session.send(trimmed) { [weak self, weak answerView] event in
            switch event {
                // the only event off the main queue: it lands in the message's buffer and is drawn on the next frame
                case .text(let delta): answerView?.appendStreamedText(delta)
                case .status(let line): self?.setStatus(line)
                case .finished(let answer): self?.endExchange(answer, nil)
                case .failed(let message): self?.endExchange(nil, message)
            }
        }
    }

    /// a failure that arrives after some text keeps that text, so the answer view is finalised either way
    private func endExchange(_ answer: String?, _ error: String?) {
        if let error { Logger.error { error } }
        setStreaming(false)
        setStatus(error, isError: error != nil)
        makeFirstResponder(composer)
        guard let answerView else { return }
        self.answerView = nil
        let final = answer ?? answerView.text
        guard !final.isEmpty else {
            transcriptView.remove(answerView)
            return
        }
        answerView.endStreaming(final)
    }

    private func appendMessage(_ role: ChatMessage.Role) -> ChatMessageView {
        let messageView = ChatMessageView(role)
        messageView.onContentChanged = { [weak self] in self?.transcriptDidChange() }
        messageView.onTypedInto = { [weak self] event in self?.focusComposer(event) }
        transcriptView.append(messageView)
        stickToBottom = true
        return messageView
    }

    private func transcriptDidChange() {
        stickToBottom = stickToBottom || isScrolledToBottom()
        transcriptView.needsLayout = true
        transcriptFade.updateFade()
    }

    private func isScrolledToBottom() -> Bool {
        let visible = scrollView.contentView.documentVisibleRect
        return visible.maxY >= transcriptView.bounds.height - 8
    }

    /// laying out doesn't move the transcript on its own, and scrolling to where we already are would round-trip
    /// back through the clip view's bounds notification for nothing
    private func scrollToBottom() {
        let offset = max(0, transcriptView.bounds.height - scrollView.contentView.bounds.height)
        guard abs(scrollView.contentView.bounds.origin.y - offset) > 0.5 else { return }
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: offset))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func setStreaming(_ isStreaming: Bool) {
        self.isStreaming = isStreaming
        sendButton.image = isStreaming ? Self.stopImage : Self.sendImage
        sendButton.toolTip = isStreaming
            ? NSLocalizedString("Stop", comment: "")
            : NSLocalizedString("Send", comment: "")
        if isStreaming {
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
        }
        refreshSendEnabled()
    }

    /// the only part of the send button that follows the composer rather than the exchange, so it is the only part
    /// a keystroke touches
    private func refreshSendEnabled() {
        sendButton.isEnabled = isStreaming || composer.string.contains { !$0.isWhitespace }
    }

    private func setStatus(_ text: String?, isError: Bool = false) {
        let wasVisible = !statusLabel.isHidden
        statusLabel.stringValue = text ?? ""
        statusLabel.textColor = isError ? .systemRed : .secondaryLabelColor
        statusLabel.isHidden = text == nil
        spinner.isHidden = text == nil || isError
        if wasVisible != !statusLabel.isHidden {
            content.needsLayout = true
        }
    }

    @objc private func sendButtonPressed() {
        if session.isStreaming {
            session.cancel()
        } else {
            submit(composer.string)
        }
    }

    private func focusComposer(_ event: NSEvent?) {
        makeFirstResponder(composer)
        guard let event else { return }
        composer.keyDown(with: event)
    }

    private func layoutContents() {
        let composerTop = layoutComposerRow()
        let transcriptBottom = statusLabel.isHidden ? composerTop : layoutStatusRow(composerTop)
        layoutTranscript(transcriptBottom)
    }

    private func layoutComposerRow() -> CGFloat {
        let width = content.bounds.width
        let composerWidth = width - Self.padding * 2 - Self.sendButtonSize - Self.rowSpacing
        let insetHeight = Self.composerInset.top + Self.composerInset.bottom
        let composerHeight = composer.heightThatFits(composerWidth - Self.composerInset.left - Self.composerInset.right) + insetHeight
        let rowHeight = max(composerHeight, Self.sendButtonSize)
        composerScrollView.frame = NSRect(x: Self.padding, y: Self.padding + (rowHeight - composerHeight) * 0.5,
                                          width: composerWidth, height: composerHeight)
        sendButton.frame = NSRect(x: width - Self.padding - Self.sendButtonSize,
                                  y: Self.padding + (rowHeight - Self.sendButtonSize) * 0.5,
                                  width: Self.sendButtonSize, height: Self.sendButtonSize)
        return Self.padding + rowHeight
    }

    private func layoutStatusRow(_ y: CGFloat) -> CGFloat {
        let top = y + Self.rowSpacing
        spinner.frame = NSRect(x: Self.padding, y: top, width: Self.statusHeight, height: Self.statusHeight)
        let labelX = spinner.isHidden ? Self.padding : Self.padding + Self.statusHeight + 5
        let width = max(0, content.bounds.width - labelX - Self.padding)
        statusLabel.frame = NSRect(x: labelX, y: top, width: width, height: Self.statusHeight)
        return top + Self.statusHeight + Self.rowSpacing
    }

    private func layoutTranscript(_ y: CGFloat) {
        let width = content.bounds.width - Self.padding * 2
        transcriptFade.frame = NSRect(x: Self.padding, y: y, width: width, height: max(0, contentLayoutRect.maxY - y))
        // the transcript sizes itself to the clip view it sits in, so a new scroll view width has to re-wrap it
        transcriptView.needsLayout = true
    }

    private func positionOnPreferredScreen() {
        let screenFrame = NSScreen.preferred.visibleFrame
        let step = CGFloat(Self.panels.count - 1).truncatingRemainder(dividingBy: Self.cascadeCount) * Self.cascadeStep
        let x = (screenFrame.midX - frame.width * 0.5 + step).rounded()
        let y = (screenFrame.midY - frame.height * 0.5 - step).rounded()
        setFrameOrigin(NSPoint(x: min(x, screenFrame.maxX - frame.width), y: max(y, screenFrame.minY)))
    }

    private func configureTranscript() {
        scrollView.contentView = ChatClipView()
        scrollView.documentView = transcriptView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        transcriptView.onLaidOut = { [weak self] in
            guard let self, self.stickToBottom else { return }
            self.scrollToBottom()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(transcriptScrolled),
                                               name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        scrollView.contentView.postsBoundsChangedNotifications = true
    }

    private func configureComposer() {
        composer.placeholder = NSLocalizedString("Ask a follow-up…", comment: "")
        composer.onSubmit = { [weak self] in self?.submit(self?.composer.string ?? "") }
        composer.onCancel = { [weak self] in self?.session.cancel() }
        composer.onTextChanged = { [weak self] in
            guard let self else { return }
            refreshSendEnabled()
            content.needsLayout = true
        }
        composerScrollView.documentView = composer
        composerScrollView.drawsBackground = false
        composerScrollView.hasVerticalScroller = false
        composerScrollView.automaticallyAdjustsContentInsets = false
        composerScrollView.contentInsets = Self.composerInset
        sendButton.image = Self.sendImage
        sendButton.imagePosition = .imageOnly
        sendButton.isBordered = false
        sendButton.contentTintColor = .systemAccentColor
        sendButton.isEnabled = false
        sendButton.target = self
        sendButton.action = #selector(sendButtonPressed)
    }

    private func configureStatus() {
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.isHidden = true
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.isHidden = true
    }

    private func configureTitlebarAccessory() {
        let button = NSButton()
        button.target = self
        button.action = #selector(copyTranscript)
        button.image = Self.copyImage
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = NSLocalizedString("Copy transcript (⇧⌘C)", comment: "")
        button.keyEquivalent = "c"
        button.keyEquivalentModifierMask = [.command, .shift]
        button.frame = NSRect(x: 0, y: Self.buttonMargin, width: Self.copyButtonSize.width, height: Self.copyButtonSize.height)
        button.autoresizingMask = [.minYMargin, .maxYMargin]
        let container = NSView(frame: NSRect(x: 0, y: 0, width: Self.titlebarAccessoryWidth,
                                             height: Self.copyButtonSize.height + Self.buttonMargin * 2))
        container.addSubview(button)
        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = container
        accessory.layoutAttribute = .right
        addTitlebarAccessoryViewController(accessory)
    }

    private func updateTitle(_ text: String) {
        fullTitle = text
        titleFittedWidth = nil
        refreshTitle()
    }

    /// AppKit measures the title against the whole titlebar, so a long one runs under the copy button before it
    /// ellipsises. Cutting the string ourselves brings the ellipsis forward to where the button starts
    private func refreshTitle() {
        let leading = (standardWindowButton(.zoomButton)?.frame.maxX ?? 0) + Self.titleLeadingGap
        let available = frame.width - leading - Self.titlebarAccessoryWidth - Self.titleTrailingGap
        guard available != titleFittedWidth else { return }
        titleFittedWidth = available
        let shown = Self.titleThatFits(fullTitle, available)
        guard shown != title else { return }
        title = shown
    }

    private static func titleThatFits(_ text: String, _ maxWidth: CGFloat) -> String {
        let attributes = [NSAttributedString.Key.font: titleFont]
        guard measuredWidth(text, attributes) > maxWidth else { return text }
        let characters = Array(text)
        var low = 0
        var high = characters.count
        while low < high {
            let mid = (low + high + 1) / 2
            if measuredWidth(String(characters.prefix(mid)) + ellipsis, attributes) <= maxWidth {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return String(characters.prefix(low)) + ellipsis
    }

    private static func measuredWidth(_ text: String, _ attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        (text as NSString).size(withAttributes: attributes).width
    }

    @objc private func transcriptScrolled() {
        stickToBottom = isScrolledToBottom()
        transcriptFade.updateFade()
    }
}

extension ChatPanel: NSWindowDelegate {
    func windowDidResize(_ notification: Notification) {
        refreshTitle()
    }

    func windowWillClose(_ notification: Notification) {
        Logger.info { "" }
        session.cancel()
        transcriptView.teardown()
        NotificationCenter.default.removeObserver(self)
        Self.panels.removeAll { $0 === self }
    }
}

/// the window's contents are laid out by hand in `layout`, which runs when the view is marked as needing it.
/// a frame change doesn't mark it, so a resized window would otherwise keep the layout it was first shown with
private class ChatContentView: NSView {
    var onLayout: (() -> Void)?

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        onLayout?()
    }
}
