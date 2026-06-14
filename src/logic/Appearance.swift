import Cocoa

class Appearance {
    // size
    static var resolvedSize = AppearanceSizePreference.medium
    static var windowPadding = CGFloat(1000)
    static var windowCornerRadius = CGFloat(1000)
    static var cellCornerRadius = CGFloat(1000)
    static var edgeInsetsSize = CGFloat(1000)
    static var maxWidthOnScreen = CGFloat(1000)
    static var iconSize = CGFloat(1000)
    static var fontHeight = CGFloat(3)
    static var font = NSFont.systemFont(ofSize: fontHeight)
    static var windowMinWidthInRow = CGFloat(1000)
    static var windowMaxWidthInRow = CGFloat(1000)

    // size: constants
    static let maxHeightOnScreen = CGFloat(0.8)
    static let interCellPadding = CGFloat(1)
    static let intraCellPadding = CGFloat(5)
    static let appIconLabelSpacing = CGFloat(2)

    // theme
    static var fontColor = NSColor.red
    static var imagesShadowColor = NSColor.red // for icon, thumbnail and windowless images

    // theme: constants
    static let highlightBorderWidth = CGFloat(2)
    static let enablePanelShadow = true
    static var highlightFocusedBackgroundColor: NSColor { get { NSColor.systemAccentColor.withAlphaComponent(0.2) } }
    static var highlightHoveredBackgroundColor: NSColor { get { NSColor.systemAccentColor.withAlphaComponent(0.1) } }
    static var highlightFocusedBorderColor: NSColor { get { NSColor.systemAccentColor } }
    static var highlightHoveredBorderColor: NSColor { get { NSColor.systemAccentColor.withAlphaComponent(0.7) } }
    static var searchMatchHighlightColor: NSColor { get { NSColor.systemYellow.withAlphaComponent(0.5) } }
    static var searchMatchForegroundColor: NSColor { get { NSColor(calibratedWhite: 0.12, alpha: 1) } }

    private static var currentSize: AppearanceSizePreference { Preferences.appearanceSize }
    static var currentTheme: AppearanceThemePreference {
        if Preferences.appearanceTheme == .system {
            return NSApp.effectiveAppearance.getThemeName()
        } else {
            return Preferences.appearanceTheme
        }
    }

    static func update() {
        updateSize()
        updateTheme()
    }

    private static func updateSize() {
        maxWidthOnScreen = AppearanceTestable.comfortableWidth(NSScreen.preferred.physicalSize().map { $0.width })
        applySize(currentSize == .auto ? .large : currentSize)
    }

    static func applySize(_ size: AppearanceSizePreference) {
        resolvedSize = size
        titlesSize(size)
        updateFont()
    }

    private static func updateTheme() {
        if currentTheme == .dark {
            darkTheme()
        } else {
            lightTheme()
        }
    }

    private static func titlesSize(_ size: AppearanceSizePreference) {
        windowPadding = 18
        windowCornerRadius = 23
        cellCornerRadius = 10
        edgeInsetsSize = 7
        windowMinWidthInRow = 0.6
        windowMaxWidthInRow = 0.9
        switch size {
            case .small:
                iconSize = 18
                fontHeight = 13
            case .medium:
                iconSize = 24
                fontHeight = 14
            case .large, .auto:
                iconSize = 30
                fontHeight = 16
        }
    }

    private static func updateFont() {
        font = NSFont.systemFont(ofSize: fontHeight, weight: .medium)
    }

    private static func lightTheme() {
        fontColor = .black.withAlphaComponent(0.8)
        imagesShadowColor = .gray.withAlphaComponent(0.8)
    }

    private static func darkTheme() {
        fontColor = .white.withAlphaComponent(0.85)
        imagesShadowColor = .gray.withAlphaComponent(0.8)
    }
}
