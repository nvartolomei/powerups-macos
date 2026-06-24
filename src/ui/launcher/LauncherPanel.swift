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
    /// the row whose action is in flight (e.g. opening a VS Code recent), shown with a spinner until the launcher hides
    private var activatingIndex: Int?
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
        searchField.controlSize = .extraLarge
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
        if let glassView = effectView as? LiquidGlassEffectView {
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
        activatingIndex = index
        Launcher.activate(result)
    }

    /// keep the panel up with a spinner on the row being activated, for actions that take a moment to bring another
    /// app forward; the launcher hides once that work reports done (or when the target app steals key from the panel)
    func beginActivationProgress() {
        rowViews[safe: activatingIndex ?? -1]?.setLoading()
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
    /// the spinner reads lighter than a full-bleed app icon, so it sits smaller and centered within the icon's slot
    private static let spinnerSize = CGFloat(20)
    private static let horizontalPadding = CGFloat(10)
    private static let verticalPadding = CGFloat(10)
    private static let minHeight = CGFloat(44)
    private static let typeLabelSpacing = CGFloat(10)
    private static let labelFontSize = CGFloat(16)
    /// x where the label starts: past the icon and the gap after it
    private static let labelLeading = horizontalPadding + iconSize + 10
    private let indexInResults: Int
    private let icon = NSImageView(frame: .zero)
    /// replaces the icon while the row's action is bringing another app forward, so the launcher doesn't look frozen
    private let spinner = NSProgressIndicator(frame: .zero)
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
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        label.font = .systemFont(ofSize: Self.labelFontSize)
        label.lineBreakMode = .byTruncatingTail
        typeLabel.font = .systemFont(ofSize: 13)
        typeLabel.textColor = .secondaryLabelColor
        typeLabel.alignment = .right
        typeLabel.lineBreakMode = .byTruncatingTail
        addSubview(icon)
        addSubview(spinner)
        addSubview(label)
        addSubview(typeLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    func updateContent(_ result: LauncherResult, _ selected: Bool, _ width: CGFloat) -> CGFloat {
        // a reused row may have been left spinning by a prior activation; rendering fresh content clears it
        icon.isHidden = false
        spinner.stopAnimation(nil)
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        // size the type label first: the label's available width depends on how much room it reserves
        typeLabel.stringValue = result.typeLabel ?? ""
        typeLabel.isHidden = result.typeLabel == nil
        let typeSize = typeLabel.isHidden ? .zero : typeLabel.cell!.cellSize
        let labelWidth = availableLabelWidth(width, ceil(typeSize.width))
        switch result {
        case .app(let app):
            icon.image = app.icon
            label.stringValue = app.name
        case .calculation(let calculation):
            icon.image = LauncherCalculator.icon
            label.attributedStringValue = calculationLabel(calculation, labelWidth)
            // expressions have no spaces, so a line too long to fit wraps within "words"
            label.maximumNumberOfLines = 0
            label.lineBreakMode = .byCharWrapping
        case .command(let command):
            icon.image = command.icon
            label.stringValue = command.name
        case .vscodeRecent(let recent):
            icon.image = recent.icon
            label.stringValue = recent.name
        }
        // template symbols (e.g. audio output commands) tint to the appearance-following label color; full-colour app icons stay as-is
        icon.contentTintColor = (icon.image?.isTemplate ?? false) ? .labelColor : nil
        // semantic color so it follows the appearance AppKit gives the glass' contentView for legibility;
        // the calculation label carries the same color in its attributes
        label.textColor = .labelColor
        let height = layoutRow(width, typeSize, labelWidth)
        setSelected(selected)
        return height
    }

    func setSelected(_ selected: Bool) {
        layer!.backgroundColor = selected ? Appearance.highlightFocusedBackgroundColor.cgColor : NSColor.clear.cgColor
    }

    func setLoading() {
        icon.isHidden = true
        spinner.startAnimation(nil)
    }

    override func mouseDown(with event: NSEvent) {
        LauncherPanel.shared.activateResult(indexInResults)
    }

    private func layoutRow(_ width: CGFloat, _ typeSize: NSSize, _ labelWidth: CGFloat) -> CGFloat {
        let typeWidth = ceil(typeSize.width)
        let labelHeight = ceil(label.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: labelWidth, height: CGFloat.greatestFiniteMagnitude)).height)
        let height = max(Self.minHeight, labelHeight + Self.verticalPadding * 2)
        icon.frame = NSRect(x: Self.horizontalPadding, y: (height - Self.iconSize) * 0.5, width: Self.iconSize, height: Self.iconSize)
        spinner.frame = NSRect(x: icon.frame.midX - Self.spinnerSize * 0.5, y: icon.frame.midY - Self.spinnerSize * 0.5, width: Self.spinnerSize, height: Self.spinnerSize)
        label.frame = NSRect(x: Self.labelLeading, y: (height - labelHeight) * 0.5, width: labelWidth, height: labelHeight)
        let typeHeight = ceil(typeSize.height)
        typeLabel.frame = NSRect(x: width - Self.horizontalPadding - typeWidth, y: (height - typeHeight) * 0.5, width: typeWidth, height: typeHeight)
        return height
    }

    /// width left for the label after the icon, paddings, and (when shown) the right-aligned type label
    private func availableLabelWidth(_ width: CGFloat, _ typeWidth: CGFloat) -> CGFloat {
        let reservedRight = typeWidth == 0 ? 0 : typeWidth + Self.typeLabelSpacing
        return width - Self.labelLeading - Self.horizontalPadding - reservedRight
    }

    /// the emphasized "= result" sits inline after the expression while the row fits; once it would overflow
    /// it drops to its own line, so a long answer stays readable instead of wrapping in the middle of a number
    private func calculationLabel(_ calculation: LauncherCalculation, _ labelWidth: CGFloat) -> NSAttributedString {
        let regular = NSFont.systemFont(ofSize: Self.labelFontSize)
        let color = NSColor.labelColor
        let result = NSAttributedString(string: "= " + calculation.display, attributes: [.font: NSFont.systemFont(ofSize: Self.labelFontSize, weight: .semibold), .foregroundColor: color])
        func labeled(_ separator: String) -> NSAttributedString {
            let attributed = NSMutableAttributedString(string: calculation.evaluatedExpression + separator, attributes: [.font: regular, .foregroundColor: color])
            attributed.append(result)
            return attributed
        }
        let inline = labeled(" ")
        guard ceil(inline.size().width) > labelWidth else { return inline }
        return labeled("\n")
    }
}
