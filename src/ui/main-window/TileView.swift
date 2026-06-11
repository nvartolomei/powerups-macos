import Cocoa

class TileView: FlippedView {
    static let noOpenWindowToolTip = NSLocalizedString("App is running but has no open window", comment: "")
    // when calculating the width of a nstextfield, somehow we need to add this suffix to get the correct width
    static let extraTextForPadding = "lmnopqrstuvw"

    var window_: Window?
    var appIcon = LightImageLayer()
    var label = TileTitleView(font: Appearance.font)
    var statusIcons = StatusIconsView()
    var dockLabelIcon = TileFontIconView(badgeSize: TileFontIconView.badgeBaseSize(forIconSize: TileView.iconSize().width))
    var windowlessAppIndicator = WindowlessAppIndicator(tooltip: TileView.noOpenWindowToolTip)
    private var fullTitle = ""
    private var fullTitleWidth = CGFloat(0)

    var mouseUpCallback: (() -> Void)!
    var mouseMovedCallback: (() -> Void)!

    // for VoiceOver cursor
    override var canBecomeKeyView: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func isAccessibilityElement() -> Bool { true }

    func mouseMoved() {
        updateLabelTooltipIfNeeded()
        mouseMovedCallback()
    }

    private func updateLabelTooltipIfNeeded() {
        label.toolTip = fullTitleWidth >= label.frame.size.width ? fullTitle : nil
    }

    convenience init() {
        self.init(frame: .zero)
        setupView()
    }

    /// The frame used by TileUnderLayer to position the highlight rectangle. It covers the full cell.
    var highlightFrame: CGRect {
        return CGRect(origin: .zero, size: frame.size)
    }

    func updateRecycledCellWithNewContent(_ element: Window, _ index: Int, _ newHeight: CGFloat) {
        window_ = element
        label.toolTip = nil
        updateValues(element, index, newHeight)
        updateSizes(newHeight)
        updatePositions(newHeight)
        applySearchHighlight()
    }

    func updateDockLabelIcon(_ dockLabel: String?) {
        assignIfDifferent(&dockLabelIcon.isHidden, dockLabel == nil || Preferences.hideAppBadges || Appearance.iconSize == 0)
        if !dockLabelIcon.isHidden, let dockLabel {
            dockLabelIcon.setText(dockLabel)
            dockLabelIcon.setAccessibilityLabel(getAccessibilityTextForBadge(dockLabel))
        }
    }

    private func setupView() {
        setAccessibilityChildren([])
        wantsLayer = true
        appIcon.applyShadow(TileView.makeAppIconShadow(Appearance.imagesShadowColor))
        dockLabelIcon.shadow = TileView.makeShadow(Appearance.imagesShadowColor)
        layer!.addSublayer(appIcon)
        addSubview(dockLabelIcon)
        label.fixHeight()
        setSubviewAbove(windowlessAppIndicator)
        addSubviews([label, statusIcons])
    }

    private func updateAppIcon(_ element: Window, _ title: String) {
        let appIconSize = TileView.iconSize()
        appIcon.updateContents(element.icon, appIconSize)
    }

    private func updateValues(_ element: Window, _ index: Int, _ newHeight: CGFloat) {
        assignIfDifferent(&windowlessAppIndicator.isHidden, !element.isWindowlessApp)
        statusIcons.update(
            isHidden: element.isHidden && !Preferences.hideStatusIcons,
            isFullscreen: element.isFullscreen && !Preferences.hideStatusIcons,
            isMinimized: element.isMinimized && !Preferences.hideStatusIcons,
            showSpace: !(element.isWindowlessApp || Spaces.isSingleSpace() || Preferences.hideSpaceNumberLabels || (
                Preferences.spacesToShow[App.shortcutIndex] == .visible && (
                    NSScreen.screens.count < 2 || Preferences.screensToShow[App.shortcutIndex] == .showingAltTab
                )
            ))
        )
        let title = getAppOrAndWindowTitle()
        let labelChanged = label.stringValue != title
        if labelChanged {
            label.stringValue = title
            setAccessibilityLabel(title)
        }
        fullTitle = title
        fullTitleWidth = label.cell!.cellSize.width
        label.updateTruncationModeIfNeeded()
        if statusIcons.spaceVisible {
            let spaceIndex = element.spaceIndexes.first
            if element.isOnAllSpaces || (spaceIndex != nil && spaceIndex! > 30) {
                statusIcons.setSpaceStar()
            } else if let spaceIndex {
                statusIcons.setSpaceNumber(spaceIndex)
            }
        }
        updateAppIcon(element, title)
        updateDockLabelIcon(element.dockLabel)
        setAccessibilityHelp(getAccessibilityHelp(element.application.localizedName, element.dockLabel))
        mouseUpCallback = { () -> Void in App.focusSelectedWindow(element) }
        mouseMovedCallback = { () -> Void in Windows.updateSelectedAndHoveredWindowIndex(index, true) }
    }

    private func applySearchHighlight() {
        let attributes = baseTitleAttributes()
        let query = Search.normalizedQuery(Windows.searchQuery)
        if query.isEmpty {
            label.attributedStringValue = NSAttributedString(string: fullTitle, attributes: attributes)
            return
        }
        let clippingAttributes = baseTitleAttributes(true)
        let spanRanges = searchSpanRanges()
        let titleLength = Array(fullTitle).count
        let highlightedIndexes = highlightedIndexes(spanRanges, titleLength)
        let truncation = truncatedDisplay(fullTitle, maxWidth: label.frame.size.width, mode: label.lineBreakMode, attributes: clippingAttributes)
        let attributed = NSMutableAttributedString(string: truncation.text, attributes: clippingAttributes)
        for range in visibleHighlightRanges(truncation.visibleToOriginal, highlightedIndexes) {
            attributed.addAttribute(TileTitleView.searchHighlightBackgroundKey, value: Appearance.searchMatchHighlightColor, range: range)
            attributed.addAttribute(.foregroundColor, value: Appearance.searchMatchForegroundColor, range: range)
        }
        let visibleOriginalIndexes = Set(truncation.visibleToOriginal.compactMap { $0 })
        let hasHiddenHighlights = highlightedIndexes.contains { !visibleOriginalIndexes.contains($0) }
        if hasHiddenHighlights, let ellipsisIndex = truncation.ellipsisIndex {
            let range = NSRange(location: ellipsisIndex, length: 1)
            attributed.addAttribute(TileTitleView.searchHighlightBackgroundKey, value: Appearance.searchMatchHighlightColor, range: range)
            attributed.addAttribute(.foregroundColor, value: Appearance.searchMatchForegroundColor, range: range)
        }
        label.attributedStringValue = attributed
    }

    private func baseTitleAttributes(_ forceClipping: Bool = false) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = label.alignment
        paragraphStyle.baseWritingDirection = .leftToRight
        paragraphStyle.lineBreakMode = forceClipping ? .byClipping : label.lineBreakMode
        return [.foregroundColor: Appearance.fontColor, .font: Appearance.font, .paragraphStyle: paragraphStyle]
    }

    private func searchSpanRanges() -> [NSRange] {
        var spanRanges = [NSRange]()
        if Preferences.onlyShowApplications() || Preferences.showTitles == .appName {
            for result in window_?.swAppResults ?? [] {
                spanRanges.append(NSRange(location: result.span.lowerBound, length: result.span.count))
            }
            return spanRanges
        }
        if Preferences.showTitles == .appNameAndWindowTitle {
            let appName = window_?.application.localizedName ?? ""
            let offset = appName.isEmpty ? 0 : (appName + " - ").count
            for result in window_?.swAppResults ?? [] {
                spanRanges.append(NSRange(location: result.span.lowerBound, length: result.span.count))
            }
            for result in window_?.swTitleResults ?? [] {
                spanRanges.append(NSRange(location: offset + result.span.lowerBound, length: result.span.count))
            }
            return spanRanges
        }
        for result in window_?.swTitleResults ?? [] {
            spanRanges.append(NSRange(location: result.span.lowerBound, length: result.span.count))
        }
        return spanRanges
    }

    private func highlightedIndexes(_ ranges: [NSRange], _ titleLength: Int) -> Set<Int> {
        var indexes = Set<Int>()
        for range in ranges {
            if range.length <= 0 { continue }
            let start = max(0, range.location)
            let end = min(titleLength, start + range.length)
            if start >= end { continue }
            for index in start..<end {
                indexes.insert(index)
            }
        }
        return indexes
    }

    private func visibleHighlightRanges(_ visibleToOriginal: [Int?], _ highlightedIndexes: Set<Int>) -> [NSRange] {
        var ranges = [NSRange]()
        var runStart: Int?
        for (displayIndex, originalIndex) in visibleToOriginal.enumerated() {
            let highlighted = originalIndex.flatMap { highlightedIndexes.contains($0) } ?? false
            if highlighted {
                if runStart == nil {
                    runStart = displayIndex
                }
            } else if let runStartValue = runStart {
                ranges.append(NSRange(location: runStartValue, length: displayIndex - runStartValue))
                runStart = nil
            }
        }
        if let runStart {
            ranges.append(NSRange(location: runStart, length: visibleToOriginal.count - runStart))
        }
        return ranges
    }

    private func truncatedDisplay(_ title: String, maxWidth: CGFloat, mode: NSLineBreakMode, attributes: [NSAttributedString.Key: Any]) -> (text: String, visibleToOriginal: [Int?], ellipsisIndex: Int?) {
        let chars = Array(title)
        if chars.isEmpty { return ("", [], nil) }
        if maxWidth <= 0 { return ("", [], nil) }
        if measuredWidth(title, attributes) <= maxWidth {
            return (title, Array(0..<chars.count).map { Optional($0) }, nil)
        }
        let ellipsis = "…"
        if measuredWidth(ellipsis, attributes) > maxWidth {
            return (ellipsis, [nil], 0)
        }
        if mode == .byTruncatingHead {
            var low = 0
            var high = chars.count
            while low < high {
                let mid = (low + high + 1) / 2
                let candidate = ellipsis + String(chars.suffix(mid))
                if measuredWidth(candidate, attributes) <= maxWidth {
                    low = mid
                } else {
                    high = mid - 1
                }
            }
            let suffixCount = low
            let suffixStart = chars.count - suffixCount
            let text = ellipsis + String(chars.suffix(suffixCount))
            let mapping = [Int?](arrayLiteral: nil) + Array(suffixStart..<chars.count).map { Optional($0) }
            return (text, mapping, 0)
        }
        if mode == .byTruncatingMiddle {
            var leftCount = (chars.count + 1) / 2
            var rightStart = leftCount
            var candidate = String(chars.prefix(leftCount)) + ellipsis + String(chars.suffix(chars.count - rightStart))
            while measuredWidth(candidate, attributes) > maxWidth && (leftCount > 0 || rightStart < chars.count) {
                if rightStart < chars.count {
                    rightStart += 1
                }
                candidate = String(chars.prefix(leftCount)) + ellipsis + String(chars.suffix(chars.count - rightStart))
                if measuredWidth(candidate, attributes) <= maxWidth {
                    break
                }
                if leftCount > 0 {
                    leftCount -= 1
                }
                candidate = String(chars.prefix(leftCount)) + ellipsis + String(chars.suffix(chars.count - rightStart))
            }
            if measuredWidth(candidate, attributes) > maxWidth {
                return (ellipsis, [nil], 0)
            }
            let text = String(chars.prefix(leftCount)) + ellipsis + String(chars.suffix(chars.count - rightStart))
            let mapping = Array(0..<leftCount).map { Optional($0) } + [nil] + Array(rightStart..<chars.count).map { Optional($0) }
            return (text, mapping, leftCount)
        }
        var low = 0
        var high = chars.count
        while low < high {
            let mid = (low + high + 1) / 2
            let candidate = String(chars.prefix(mid)) + ellipsis
            if measuredWidth(candidate, attributes) <= maxWidth {
                low = mid
            } else {
                high = mid - 1
            }
        }
        let prefixCount = low
        let text = String(chars.prefix(prefixCount)) + ellipsis
        let mapping = Array(0..<prefixCount).map { Optional($0) } + [nil]
        return (text, mapping, prefixCount)
    }

    private func measuredWidth(_ text: String, _ attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        (text as NSString).size(withAttributes: attributes).width
    }

    private func updateSizes(_ newHeight: CGFloat) {
        setFrameWidthHeight(newHeight)
        let hWidth = frame.width - Appearance.edgeInsetsSize * 2
        let labelWidth = hWidth - appIcon.frame.width - Appearance.appIconLabelSpacing - statusIcons.totalWidth
        label.setWidth(labelWidth)
    }

    private func updatePositions(_ newHeight: CGFloat) {
        let edgeInsets = Appearance.edgeInsetsSize
        assignIfDifferent(&appIcon.frame.origin, NSPoint(x: edgeInsets, y: edgeInsets))
        let hWidth = frame.width - edgeInsets * 2
        let hHeight = max(appIcon.frame.height, TilesView.layoutCache.labelHeight)
        if App.shared.userInterfaceLayoutDirection == .rightToLeft {
            assignIfDifferent(&appIcon.frame.origin.x, edgeInsets + hWidth - appIcon.frame.width)
        }
        statusIcons.layoutIcons(hWidth: hWidth, hHeight: hHeight, edgeInsets: edgeInsets)
        let labelWidth = hWidth - appIcon.frame.width - Appearance.appIconLabelSpacing - statusIcons.totalWidth
        let labelX: CGFloat
        if App.shared.userInterfaceLayoutDirection == .leftToRight {
            labelX = appIcon.frame.maxX + Appearance.appIconLabelSpacing
        } else {
            labelX = edgeInsets + hWidth - appIcon.frame.width - Appearance.appIconLabelSpacing - labelWidth
        }
        assignIfDifferent(&label.frame.origin.x, labelX)
        assignIfDifferent(&label.frame.origin.y, edgeInsets + ((hHeight - TilesView.layoutCache.labelHeight) / 2).rounded())
        updateWindowlessAppIndicatorPosition()
        updateDockLabelIconPosition()
    }

    private func updateDockLabelIconPosition() {
        let iconSize = max(appIcon.frame.width, appIcon.frame.height)
        let offset = (iconSize * 0.05).rounded()
        let badgeTopRightX = appIcon.frame.maxX + offset
        let badgeTopRightY = appIcon.frame.minY - offset
        assignIfDifferent(&dockLabelIcon.frame.origin.x, badgeTopRightX - dockLabelIcon.frame.width)
        assignIfDifferent(&dockLabelIcon.frame.origin.y, badgeTopRightY)
    }

    private func updateWindowlessAppIndicatorPosition() {
        guard !windowlessAppIndicator.isHidden else { return }
        assignIfDifferent(&windowlessAppIndicator.frame.origin.x, windowlessIndicatorXPosition())
        assignIfDifferent(&windowlessAppIndicator.frame.origin.y, windowlessIndicatorYPosition())
    }

    private func windowlessIndicatorXPosition() -> CGFloat {
        return (appIcon.frame.midX - windowlessAppIndicator.frame.width / 2).rounded()
    }

    private func windowlessIndicatorYPosition() -> CGFloat {
        return (appIcon.frame.maxY - windowlessAppIndicator.frame.height + 5).rounded()
    }

    private func getAppOrAndWindowTitle() -> String {
        let appName = window_?.application.localizedName
        let windowTitle = window_?.title
        if Preferences.onlyShowApplications() || Preferences.showTitles == .appName {
            return appName ?? ""
        } else if Preferences.showTitles == .appNameAndWindowTitle {
            return [appName, windowTitle].compactMap { $0 }.joined(separator: " - ")
        }
        return windowTitle ?? ""
    }

    private func setFrameWidthHeight(_ newHeight: CGFloat) {
        let contentWidth = TileView.maxThumbnailWidth() - Appearance.edgeInsetsSize * 2
        let frameWidth = (contentWidth + Appearance.edgeInsetsSize * 2).rounded()
        let widthMin = TileView.minThumbnailWidth()
        let width = max(frameWidth, widthMin).rounded()
        assignIfDifferent(&frame.size.width, width)
        assignIfDifferent(&frame.size.height, newHeight)
    }

    private func getAccessibilityHelp(_ appName: String?, _ dockLabel: String?) -> String {
        [appName, dockLabel.map { getAccessibilityTextForBadge($0) }]
            .compactMap { $0 }
            .joined(separator: " - ")
    }

    private func getAccessibilityTextForBadge(_ dockLabel: String) -> String {
        if let dockLabelInt = Int(dockLabel) {
            return "Red badge with number \(dockLabelInt)"
        }
        return "Red badge"
    }

    static func makeShadow(_ color: NSColor?) -> NSShadow? {
        let shadow = NSShadow()
        shadow.shadowColor = color
        shadow.shadowOffset = .zero
        shadow.shadowBlurRadius = 1
        return shadow
    }

    static func makeAppIconShadow(_ color: NSColor?) -> NSShadow? {
        guard let color else { return nil }
        let shadow = NSShadow()
        shadow.shadowColor = color.withAlphaComponent(0.4)
        shadow.shadowOffset = NSSize(width: 0.1, height: 1)
        shadow.shadowBlurRadius = 2
        return shadow
    }

    static func maxThumbnailWidth(_ screen: NSScreen = NSScreen.preferred) -> CGFloat {
        return TilesPanel.maxThumbnailsWidth(screen) * Appearance.windowMaxWidthInRow - Appearance.interCellPadding * 2
    }

    static func widthOfComfortableReadability() -> CGFloat? {
        let labTitleView = TileTitleView(font: Appearance.font)
        labTitleView.stringValue = "abcdefghijklmnopqrstuvwxyz-abcdefghijklmnopqrstuvwxyz-abcdefghijklmnopqrstuvwxyz" + extraTextForPadding
        return labTitleView.cell!.cellSize.width
    }

    static func widthOfLongestTitle() -> CGFloat? {
        let labTitleView = TileTitleView(font: Appearance.font)
        var maxWidth = CGFloat(0)
        for window in Windows.list {
            guard window.shouldShowTheUser else { continue }
            labTitleView.stringValue = window.title + extraTextForPadding
            let width = labTitleView.cell!.cellSize.width
            if width > maxWidth {
                maxWidth = width
            }
        }
        guard maxWidth > 0 else { return nil }
        return maxWidth
    }

    static func minThumbnailWidth(_ screen: NSScreen = NSScreen.preferred) -> CGFloat {
        return TilesPanel.maxThumbnailsWidth(screen) * Appearance.windowMinWidthInRow - Appearance.interCellPadding * 2
    }

    static func iconSize() -> NSSize {
        return NSSize(width: Appearance.iconSize, height: Appearance.iconSize)
    }

    static func height(_ labelHeight: CGFloat) -> CGFloat {
        return max(TileView.iconSize().height, labelHeight) + Appearance.edgeInsetsSize * 2
    }
}
