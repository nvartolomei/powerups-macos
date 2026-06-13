import Cocoa

class Launcher {
    static let maxResults = 10
    private static var appsCache = [LauncherApp]()
    private static let applicationsFolders = [
        URL(fileURLWithPath: "/Applications", isDirectory: true),
        URL(fileURLWithPath: "/System/Applications", isDirectory: true),
    ]
    private static let settingsExtensionsFolder = URL(fileURLWithPath: "/System/Library/ExtensionKit/Extensions", isDirectory: true)

    static func initialize() {
        _ = LauncherPanel()
        refreshAppsCacheAsync()
    }

    @objc static func toggle() {
        if LauncherPanel.shared.isVisible {
            hide()
        } else {
            show()
        }
    }

    static func show() {
        Logger.info { "" }
        if App.appIsBeingUsed { App.hideUi() }
        refreshAppsCacheAsync()
        LauncherPanel.shared.show()
    }

    static func hide() {
        guard LauncherPanel.shared.isVisible else { return }
        Logger.info { "" }
        App.orderOutWithoutChangingKeyWindow(LauncherPanel.shared)
    }

    static func results(_ query: String) -> [LauncherResult] {
        if let calculation = LauncherCalculator.evaluate(query) { return [.calculation(calculation)] }
        let commands = LauncherCommands.matching(query).map { LauncherResult.command($0) }
        let apps = matchingApps(query).prefix(maxResults - commands.count).map { LauncherResult.app($0) }
        return apps + commands
    }

    static func activate(_ result: LauncherResult) {
        switch result {
        case .app(let app): open(app)
        case .calculation(let calculation): copyToClipboard(calculation.raw)
        case .command(let command): run(command)
        }
    }

    private static func matchingApps(_ query: String) -> [LauncherApp] {
        let normalized = LauncherSearch.normalizedQuery(query)
        guard !normalized.isEmpty else { return [] }
        var matches = [(rank: Int, app: LauncherApp)]()
        for app in appsCache {
            if let rank = LauncherSearch.matchRank(normalized, app.words, app.lowercasedName) {
                matches.append((rank, app))
            }
        }
        matches.sort { $0.rank == $1.rank ? $0.app.name.localizedCaseInsensitiveCompare($1.app.name) == .orderedAscending : $0.rank < $1.rank }
        return matches.prefix(maxResults).map { $0.app }
    }

    private static func open(_ app: LauncherApp) {
        Logger.info { app.url.path }
        hide()
        if let paneId = app.paneId {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:" + paneId)!)
        } else if #available(macOS 10.15, *) {
            NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(app.url)
        }
    }

    private static func copyToClipboard(_ text: String) {
        Logger.info { text }
        hide()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private static func run(_ command: LauncherCommand) {
        Logger.info { command.keyword }
        hide()
        command.action()
    }

    private static func refreshAppsCacheAsync() {
        DispatchQueue.global(qos: .userInteractive).async {
            _ = LauncherCalculator.icon
            _ = LauncherCommand.icon
            let apps = (scanApplicationsFolders() + scanSettingsPanes())
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            DispatchQueue.main.async {
                appsCache = apps
                if LauncherPanel.shared.isVisible {
                    LauncherPanel.shared.updateResults(force: true)
                }
            }
        }
    }

    /// .app bundles at the root of the applications folders, or one folder deep (e.g. /Applications/Utilities)
    /// we can't use .skipsHiddenFiles as some apps are hidden-flagged symlinks (e.g. Safari.app since macOS 13)
    private static func scanApplicationsFolders() -> [LauncherApp] {
        var apps = [LauncherApp]()
        for folder in applicationsFolders {
            guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil, options: [.skipsPackageDescendants]) else { continue }
            while let url = enumerator.nextObject() as? URL {
                if url.lastPathComponent.hasPrefix(".") {
                    enumerator.skipDescendants()
                } else if url.pathExtension == "app" {
                    apps.append(LauncherApp(url, url.deletingPathExtension().lastPathComponent))
                    enumerator.skipDescendants()
                } else if enumerator.level >= 2 {
                    enumerator.skipDescendants()
                }
            }
        }
        return apps
    }

    /// System Settings panes are app extensions; they open via the x-apple.systempreferences URL scheme
    private static func scanSettingsPanes() -> [LauncherApp] {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: settingsExtensionsFolder, includingPropertiesForKeys: nil) else { return [] }
        var panes = [LauncherApp]()
        for url in urls where url.pathExtension == "appex" {
            guard let bundle = Bundle(url: url),
                  let attributes = bundle.infoDictionary?["EXAppExtensionAttributes"] as? [String: Any],
                  attributes["EXExtensionPointIdentifier"] as? String == "com.apple.Settings.extension.ui",
                  let paneId = bundle.bundleIdentifier,
                  let name = paneName(bundle, paneId) else { continue }
            panes.append(LauncherApp(url, name, paneId))
        }
        return panes
    }

    private static func paneName(_ bundle: Bundle, _ paneId: String) -> String? {
        // ships without a usable display name
        if paneId == "com.apple.Battery-Settings.extension" { return NSLocalizedString("Battery", comment: "") }
        // contextual pane: only shows in System Settings while headphones are connected
        if paneId == "com.apple.HeadphoneSettings" { return nil }
        return bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String ?? bundle.infoDictionary?["CFBundleDisplayName"] as? String
    }
}

enum LauncherResult {
    case app(LauncherApp)
    /// the result of evaluating the query as an arithmetic expression; activating it copies the raw value to the clipboard
    case calculation(LauncherCalculation)
    /// a built-in command matched by keyword; activating it runs its action
    case command(LauncherCommand)

    /// faint right-side label naming where a result comes from; nil for plain apps, the common case that needs no hint
    var typeLabel: String? {
        switch self {
        case .app(let app): return app.paneId == nil ? nil : NSLocalizedString("System Settings", comment: "")
        case .calculation: return NSLocalizedString("Calculator", comment: "")
        case .command: return NSLocalizedString("Command", comment: "")
        }
    }
}

struct LauncherApp {
    let url: URL
    let name: String
    /// set for System Settings panes, which open via the x-apple.systempreferences URL scheme
    let paneId: String?
    let lowercasedName: String
    let words: [[Character]]
    let icon: NSImage

    /// called on a background thread: cold icon loads hit the disk and would block the main thread on first render
    init(_ url: URL, _ name: String, _ paneId: String? = nil) {
        self.url = url
        self.name = name
        self.paneId = paneId
        lowercasedName = name.lowercased()
        words = LauncherSearch.humpWords(name)
        icon = NSWorkspace.shared.icon(forFile: url.path)
    }
}
