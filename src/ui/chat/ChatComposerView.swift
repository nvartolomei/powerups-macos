import Cocoa

class ChatComposerScrollView: NSScrollView {
    private static let cornerRadius = CGFloat(12)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer!.cornerRadius = Self.cornerRadius
        layer!.cornerCurve = .continuous
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer!.backgroundColor = NSColor.tertiarySystemFill.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// the input field: it grows with the text up to a few lines, then scrolls. return sends, shift-return breaks a line
class ChatComposerView: NSTextView {
    private static let maximumLines = 6
    private static let placeholderAttributes: [NSAttributedString.Key: Any] = [
        .font: ChatMarkdown.bodyFont,
        .foregroundColor: NSColor.placeholderTextColor,
    ]
    var placeholder = ""
    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?
    var onTextChanged: (() -> Void)?

    convenience init() {
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        self.init(frame: .zero, textContainer: container)
        font = ChatMarkdown.bodyFont
        drawsBackground = false
        isRichText = false
        // the composer is a plain input; the substitutions would rewrite quotes and dashes inside pasted code
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isVerticallyResizable = true
        isHorizontallyResizable = false
        textContainerInset = .zero
        autoresizingMask = [.width]
    }

    func heightThatFits(_ width: CGFloat) -> CGFloat {
        guard let container = textContainer, let manager = layoutManager else { return 0 }
        container.size = NSSize(width: max(1, width), height: CGFloat.greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        let lineHeight = manager.defaultLineHeight(for: ChatMarkdown.bodyFont)
        let used = ceil(manager.usedRect(for: container).height)
        return min(max(used, lineHeight), lineHeight * CGFloat(Self.maximumLines)).rounded(.up)
    }

    override func doCommand(by selector: Selector) {
        if selector == #selector(insertNewline(_:)) {
            // shift-return isn't bound to its own command, so it arrives here as a plain return: only the
            // modifiers on the event that produced it tell a new line apart from a send
            if NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false {
                insertNewlineIgnoringFieldEditor(nil)
                return
            }
            onSubmit?()
            return
        }
        if selector == #selector(cancelOperation(_:)) {
            onCancel?()
            return
        }
        super.doCommand(by: selector)
    }

    override func didChangeText() {
        super.didChangeText()
        onTextChanged?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        placeholder.draw(at: NSPoint(x: textContainerInset.width, y: textContainerInset.height),
                         withAttributes: Self.placeholderAttributes)
    }
}
