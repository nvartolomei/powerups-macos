import Cocoa

class Launcher {
    static let maxResults = 10
    private static var appsCache = [LauncherApp]()
    private static let applicationsFolders = [
        URL(fileURLWithPath: "/Applications", isDirectory: true),
        URL(fileURLWithPath: "/System/Applications", isDirectory: true),
    ]

    static func initialize() {
        _ = LauncherPanel()
        refreshAppsCacheAsync()
    }

    static func toggle() {
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
        return matchingApps(query).map { LauncherResult.app($0) }
    }

    static func activate(_ result: LauncherResult) {
        switch result {
        case .app(let app): open(app)
        case .calculation(let calculation): copyToClipboard(calculation.raw)
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
        if #available(macOS 10.15, *) {
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

    private static func refreshAppsCacheAsync() {
        DispatchQueue.global(qos: .userInteractive).async {
            _ = LauncherCalculator.icon
            let apps = scanApplicationsFolders()
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
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

enum LauncherResult {
    case app(LauncherApp)
    /// the result of evaluating the query as an arithmetic expression; activating it copies the raw value to the clipboard
    case calculation(LauncherCalculation)
}

struct LauncherApp {
    let url: URL
    let name: String
    let lowercasedName: String
    let words: [[Character]]
    let icon: NSImage

    /// called on a background thread: cold icon loads hit the disk and would block the main thread on first render
    init(_ url: URL, _ name: String) {
        self.url = url
        self.name = name
        lowercasedName = name.lowercased()
        words = LauncherSearch.humpWords(name)
        icon = NSWorkspace.shared.icon(forFile: url.path)
    }
}
