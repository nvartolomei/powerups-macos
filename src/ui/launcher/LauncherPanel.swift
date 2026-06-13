import Cocoa

class LauncherPanel: NSPanel {
    static var shared: LauncherPanel!
    private static let panelWidth = CGFloat(580)
    private static let padding = CGFloat(15)
    private static let resultsSpacing = CGFloat(10)
    override var canBecomeKey: Bool { true }
    private var effectView: EffectView!
    private let contentContainer = NSView(frame: .zero)
    private let searchField = NSSearchField(frame: .zero)
    private var rowViews = [LauncherRowView]()
    private var results = [LauncherResult]()
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
        contentContainer.addSubview(searchField)
        rowViews = (0..<Launcher.maxResults).map { LauncherRowView($0) }
        rowViews.forEach { contentContainer.addSubview($0) }
        effectView.setContent(contentContainer)
        contentView = effectView
        Self.shared = self
    }

    private func configureSearchField() {
        searchField.placeholderString = NSLocalizedString("Open application", comment: "")
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = true
        if #available(macOS 26.0, *) {
            searchField.controlSize = .extraLarge
        } else if #available(macOS 13.0, *) {
            searchField.controlSize = .large
        } else {
            searchField.controlSize = .regular
        }
        // blend into the glass panel like Spotlight: no bezel, no background, no focus ring
        searchField.isBezeled = false
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.backgroundColor = .clear
        searchField.focusRingType = .none
        searchField.font = .systemFont(ofSize: 22, weight: .regular)
        searchField.usesSingleLineMode = true
        if let cell = searchField.cell as? NSSearchFieldCell {
            cell.searchButtonCell = nil
            cell.cancelButtonCell = nil
            // a long query should scroll horizontally to follow the caret, not clip past the field's right edge
            cell.wraps = false
            cell.isScrollable = true
        }
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
        // don't pin a dark/light appearance: the liquid glass tints itself to match whatever is behind
        // the panel, and AppKit keeps the contentView legible against that tint on its own
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
        results = Launcher.results(query)
        selectedIndex = 0
        caTransaction { layoutContents() }
    }

    private func layoutContents() {
        let fieldHeight = ceil(searchField.fittingSize.height)
        let rowWidth = Self.panelWidth - Self.padding * 2
        var rowHeights = [CGFloat]()
        for (i, row) in rowViews.enumerated() {
            row.isHidden = i >= results.count
            guard i < results.count else { continue }
            rowHeights.append(row.updateContent(results[i], i == selectedIndex, rowWidth))
        }
        let resultsHeight = results.isEmpty ? 0 : Self.resultsSpacing + rowHeights.reduce(0, +)
        let height = Self.padding * 2 + fieldHeight + resultsHeight
        setContentSize(NSSize(width: Self.panelWidth, height: height))
        contentContainer.frame = NSRect(x: 0, y: 0, width: Self.panelWidth, height: height)
        searchField.frame = NSRect(x: Self.padding, y: height - Self.padding - fieldHeight, width: rowWidth, height: fieldHeight)
        var rowTop = height - Self.padding - fieldHeight - Self.resultsSpacing
        for (i, row) in rowViews.enumerated() where i < results.count {
            row.frame = NSRect(x: Self.padding, y: rowTop - rowHeights[i], width: rowWidth, height: rowHeights[i])
            rowTop -= rowHeights[i]
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

    func activateResult(_ index: Int) {
        guard let result = results[safe: index] else { return }
        Launcher.activate(result)
    }
}

extension LauncherPanel: NSSearchFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        scheduleUpdateResults()
    }

    /// a coalesced render may still be pending; updateResults is deduplicated, so flushing it first is cheap
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { Launcher.hide(); return true }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) { updateResults(); activateResult(selectedIndex); return true }
        if commandSelector == #selector(NSResponder.moveUp(_:)) { updateResults(); cycleSelectedIndex(-1); return true }
        if commandSelector == #selector(NSResponder.moveDown(_:)) { updateResults(); cycleSelectedIndex(1); return true }
        return false
    }
}

extension LauncherPanel: NSWindowDelegate {
    func windowDidBecomeKey(_ notification: Notification) {
        // avoids command+q from quitting PowerUps itself, while keeping edit shortcuts for the search field
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
    private static let verticalPadding = CGFloat(10)
    private static let minHeight = CGFloat(44)
    private static let typeLabelSpacing = CGFloat(10)
    private let indexInResults: Int
    private let icon = NSImageView(frame: .zero)
    private let label = NSTextField(labelWithString: "")
    /// faint right-aligned hint naming a result's provenance, e.g. "System Settings"; hidden for plain apps
    private let typeLabel = NSTextField(labelWithString: "")

    init(_ indexInResults: Int) {
        self.indexInResults = indexInResults
        super.init(frame: .zero)
        isHidden = true
        wantsLayer = true
        layer!.cornerRadius = 8
        icon.imageScaling = .scaleProportionallyUpOrDown
        label.font = .systemFont(ofSize: 16)
        label.lineBreakMode = .byTruncatingTail
        typeLabel.font = .systemFont(ofSize: 13)
        typeLabel.textColor = .secondaryLabelColor
        typeLabel.alignment = .right
        typeLabel.lineBreakMode = .byTruncatingTail
        addSubview(icon)
        addSubview(label)
        addSubview(typeLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    func updateContent(_ result: LauncherResult, _ selected: Bool, _ width: CGFloat) -> CGFloat {
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        switch result {
        case .app(let app):
            icon.image = app.icon
            label.stringValue = app.name
        case .calculation(let calculation):
            icon.image = LauncherCalculator.icon
            label.stringValue = calculation.evaluatedExpression + " = " + calculation.display
            // expressions have no spaces, so wrapping has to break within "words"
            label.maximumNumberOfLines = 0
            label.lineBreakMode = .byCharWrapping
        case .command(let command):
            icon.image = LauncherCommand.icon
            label.stringValue = command.name
        }
        // semantic color so it follows the appearance AppKit gives the glass' contentView for legibility
        label.textColor = .labelColor
        typeLabel.stringValue = result.typeLabel ?? ""
        typeLabel.isHidden = result.typeLabel == nil
        let height = layoutRow(width)
        setSelected(selected)
        return height
    }

    func setSelected(_ selected: Bool) {
        layer!.backgroundColor = selected ? Appearance.highlightFocusedBackgroundColor.cgColor : NSColor.clear.cgColor
    }

    override func mouseDown(with event: NSEvent) {
        LauncherPanel.shared.activateResult(indexInResults)
    }

    private func layoutRow(_ width: CGFloat) -> CGFloat {
        let labelX = Self.horizontalPadding + Self.iconSize + 10
        let typeSize = typeLabel.isHidden ? .zero : typeLabel.cell!.cellSize
        let typeWidth = ceil(typeSize.width)
        let reservedRight = typeLabel.isHidden ? 0 : typeWidth + Self.typeLabelSpacing
        let labelWidth = width - labelX - Self.horizontalPadding - reservedRight
        let labelHeight = ceil(label.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: labelWidth, height: CGFloat.greatestFiniteMagnitude)).height)
        let height = max(Self.minHeight, labelHeight + Self.verticalPadding * 2)
        icon.frame = NSRect(x: Self.horizontalPadding, y: (height - Self.iconSize) * 0.5, width: Self.iconSize, height: Self.iconSize)
        label.frame = NSRect(x: labelX, y: (height - labelHeight) * 0.5, width: labelWidth, height: labelHeight)
        let typeHeight = ceil(typeSize.height)
        typeLabel.frame = NSRect(x: width - Self.horizontalPadding - typeWidth, y: (height - typeHeight) * 0.5, width: typeWidth, height: typeHeight)
        return height
    }
}
