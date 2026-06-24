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
        let normalized = LauncherSearch.normalizedQuery(query)
        guard !normalized.isEmpty else { return [] }
        let matches = ranked(appsCache, normalized, LauncherResult.app) + ranked(LauncherCommands.all, normalized, LauncherResult.command) + ranked(LauncherVSCodeRecents.all, normalized, LauncherResult.vscodeRecent)
        return matches
            .sorted { $0.rank == $1.rank ? $0.result.name.localizedCaseInsensitiveCompare($1.result.name) == .orderedAscending : $0.rank < $1.rank }
            .prefix(maxResults)
            .map { $0.result }
    }

    static func activate(_ result: LauncherResult) {
        switch result {
        case .app(let app): open(app)
        case .calculation(let calculation): copyToClipboard(calculation.raw)
        case .command(let command): run(command)
        case .vscodeRecent(let recent): openRecent(recent)
        }
    }

    private static func ranked<T: LauncherSearchable>(_ items: [T], _ query: [Character], _ wrap: (T) -> LauncherResult) -> [(rank: Int, result: LauncherResult)] {
        items.compactMap { item in LauncherSearch.matchRank(query, item.words, item.lowercasedName).map { (rank: $0, result: wrap(item)) } }
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
        Logger.info { command.name }
        hide()
        command.action()
    }

    private static func openRecent(_ recent: LauncherRecent) {
        Logger.info { recent.folderUri }
        LauncherPanel.shared.beginActivationProgress()
        LauncherVSCodeRecents.open(recent) { hide() }
    }

    private static func refreshAppsCacheAsync() {
        DispatchQueue.global(qos: .userInteractive).async {
            _ = LauncherCalculator.icon
            _ = LauncherCommand.icon
            let apps = (scanApplicationsFolders() + scanSettingsPanes())
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            let recents = LauncherVSCodeRecents.load()
            DispatchQueue.main.async {
                appsCache = apps
                LauncherVSCodeRecents.all = recents
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
    /// a built-in command matched by name; activating it runs its action
    case command(LauncherCommand)
    /// a folder from VS Code's recently-opened list; activating it reopens the folder in VS Code
    case vscodeRecent(LauncherRecent)

    /// the row's display name; also the tie-break key when two results share a match rank
    var name: String {
        switch self {
        case .app(let app): return app.name
        case .calculation(let calculation): return calculation.display
        case .command(let command): return command.name
        case .vscodeRecent(let recent): return recent.name
        }
    }

    /// faint right-side label naming where a result comes from; nil for plain apps, the common case that needs no hint
    var typeLabel: String? {
        switch self {
        case .app(let app): return app.paneId == nil ? nil : NSLocalizedString("System Settings", comment: "")
        case .calculation: return NSLocalizedString("Calculator", comment: "")
        case .command: return NSLocalizedString("Command", comment: "")
        // the "VSCode:" prefix in the name already names the provenance, so no separate right-side hint
        case .vscodeRecent: return nil
        }
    }
}

struct LauncherApp: LauncherSearchable {
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
