import Cocoa

class LauncherPanel: NSPanel {
    static var shared: LauncherPanel!
    private static let panelWidth = CGFloat(580)
    private static let padding = CGFloat(15)
    private static let rowHeight = CGFloat(44)
    private static let resultsSpacing = CGFloat(10)
    override var canBecomeKey: Bool { true }
    private var effectView: EffectView!
    private let searchField = NSSearchField(frame: .zero)
    private var rowViews = [LauncherRowView]()
    private var results = [LauncherApp]()
    private var selectedIndex = 0
    private var topY = CGFloat(0)
    private var lastRenderedQuery: String?
    private var pendingRender: DispatchWorkItem?
    private static let renderDelay = DispatchTimeInterval.milliseconds(50)

    convenience init() {
        self.init(contentRect: .zero, styleMask: .nonactivatingPanel, backing: .buffered, defer: false)
        delegate = self
        isFloatingPanel = true
        animationBehavior = .none
        hidesOnDeactivate = false
        titleVisibility = .hidden
        backgroundColor = .clear
        collectionBehavior = .canJoinAllSpaces
        level = .popUpMenu
        // helps filter out this window from the thumbnails
        setAccessibilitySubrole(.unknown)
        setAccessibilityLabel(NSLocalizedString("Open application", comment: ""))
        configureSearchField()
        effectView = makeAppropriateEffectView()
        effectView.addSubview(searchField)
        rowViews = (0..<Launcher.maxResults).map { LauncherRowView($0) }
        rowViews.forEach { effectView.addSubview($0) }
        contentView = effectView
        Self.shared = self
    }

    private func configureSearchField() {
        searchField.placeholderString = NSLocalizedString("Open application", comment: "")
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = true
        searchField.bezelStyle = .roundedBezel
        if #available(macOS 26.0, *) {
            searchField.controlSize = .extraLarge
        } else if #available(macOS 13.0, *) {
            searchField.controlSize = .large
        } else {
            searchField.controlSize = .regular
        }
        searchField.usesSingleLineMode = true
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchFieldChanged)
    }

    @objc private func searchFieldChanged() {
        scheduleUpdateResults()
    }

    /// debounce: render once the query settles, so fast bursts of keystrokes don't render intermediate results
    private func scheduleUpdateResults() {
        pendingRender?.cancel()
        let render = DispatchWorkItem { [weak self] in
            guard let self, self.isVisible else { return }
            self.updateResults()
        }
        pendingRender = render
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.renderDelay, execute: render)
    }

    func show() {
        NSScreen.updatePreferred()
        Appearance.update()
        updateAppearance()
        searchField.stringValue = ""
        updateResults(force: true)
        repositionOnPreferredScreen()
        alphaValue = 1
        makeKeyAndOrderFront(nil)
        makeFirstResponder(searchField)
    }

    private func updateAppearance() {
        hasShadow = Appearance.enablePanelShadow
        appearance = NSAppearance(named: Appearance.currentTheme == .dark ? .vibrantDark : .vibrantLight)
        effectView.updateAppearance()
        // Appearance.windowCornerRadius can be larger than half this panel's height; we cap it
        if #available(macOS 26.0, *), let glassView = effectView as? LiquidGlassEffectView {
            glassView.cornerRadius = min(Appearance.windowCornerRadius, 26)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        Launcher.hide()
    }

    /// the search field reports edits through both its action and controlTextDidChange; we render a given query once
    func updateResults(force: Bool = false) {
        pendingRender?.cancel()
        let query = searchField.stringValue
        if !force && query == lastRenderedQuery { return }
        lastRenderedQuery = query
        results = Launcher.matchingApps(query)
        selectedIndex = 0
        caTransaction { layoutContents() }
    }

    private func layoutContents() {
        let fieldHeight = ceil(searchField.fittingSize.height)
        let rowWidth = Self.panelWidth - Self.padding * 2
        let resultsHeight = results.isEmpty ? 0 : Self.resultsSpacing + CGFloat(results.count) * Self.rowHeight
        let height = Self.padding * 2 + fieldHeight + resultsHeight
        setContentSize(NSSize(width: Self.panelWidth, height: height))
        searchField.frame = NSRect(x: Self.padding, y: height - Self.padding - fieldHeight, width: rowWidth, height: fieldHeight)
        for (i, row) in rowViews.enumerated() {
            row.isHidden = i >= results.count
            guard i < results.count else { continue }
            row.frame = NSRect(x: Self.padding, y: height - Self.padding - fieldHeight - Self.resultsSpacing - CGFloat(i + 1) * Self.rowHeight, width: rowWidth, height: Self.rowHeight)
            row.updateContent(results[i], i == selectedIndex)
        }
        setFrameOrigin(NSPoint(x: frame.origin.x, y: topY - frame.height))
    }

    private func repositionOnPreferredScreen() {
        let screenFrame = NSScreen.preferred.visibleFrame
        topY = (screenFrame.minY + screenFrame.height * 0.75).rounded()
        setFrameOrigin(NSPoint(x: (screenFrame.midX - frame.width * 0.5).rounded(), y: topY - frame.height))
    }

    private func cycleSelectedIndex(_ step: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = (selectedIndex + step + results.count) % results.count
        for (i, row) in rowViews.enumerated() where i < results.count {
            row.setSelected(i == selectedIndex)
        }
    }

    func openResult(_ index: Int) {
        guard let app = results[safe: index] else { return }
        Launcher.open(app)
    }
}

extension LauncherPanel: NSSearchFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        scheduleUpdateResults()
    }

    /// a coalesced render may still be pending; updateResults is deduplicated, so flushing it first is cheap
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { Launcher.hide(); return true }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) { updateResults(); openResult(selectedIndex); return true }
        if commandSelector == #selector(NSResponder.moveUp(_:)) { updateResults(); cycleSelectedIndex(-1); return true }
        if commandSelector == #selector(NSResponder.moveDown(_:)) { updateResults(); cycleSelectedIndex(1); return true }
        return false
    }
}

extension LauncherPanel: NSWindowDelegate {
    func windowDidBecomeKey(_ notification: Notification) {
        // avoids command+q from quitting AltTab itself, while keeping edit shortcuts for the search field
        MainMenu.toggle(false)
        MainMenu.toggleEditMenu(true)
    }

    func windowDidResignKey(_ notification: Notification) {
        Launcher.hide()
        MainMenu.toggle(true)
    }
}

private class LauncherRowView: NSView {
    private static let iconSize = CGFloat(32)
    private static let horizontalPadding = CGFloat(10)
    private let indexInResults: Int
    private let icon = NSImageView(frame: .zero)
    private let label = NSTextField(labelWithString: "")

    init(_ indexInResults: Int) {
        self.indexInResults = indexInResults
        super.init(frame: .zero)
        isHidden = true
        wantsLayer = true
        layer!.cornerRadius = 8
        icon.imageScaling = .scaleProportionallyUpOrDown
        label.font = .systemFont(ofSize: 16)
        label.lineBreakMode = .byTruncatingTail
        addSubview(icon)
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    func updateContent(_ app: LauncherApp, _ selected: Bool) {
        icon.image = app.icon
        label.stringValue = app.name
        label.textColor = Appearance.fontColor
        layoutRow()
        setSelected(selected)
    }

    func setSelected(_ selected: Bool) {
        layer!.backgroundColor = selected ? Appearance.highlightFocusedBackgroundColor.cgColor : NSColor.clear.cgColor
    }

    override func mouseDown(with event: NSEvent) {
        LauncherPanel.shared.openResult(indexInResults)
    }

    private func layoutRow() {
        icon.frame = NSRect(x: Self.horizontalPadding, y: (bounds.height - Self.iconSize) * 0.5, width: Self.iconSize, height: Self.iconSize)
        let labelHeight = ceil(label.cell!.cellSize.height)
        let labelX = Self.horizontalPadding + Self.iconSize + 10
        label.frame = NSRect(x: labelX, y: (bounds.height - labelHeight) * 0.5, width: bounds.width - labelX - Self.horizontalPadding, height: labelHeight)
    }
}
