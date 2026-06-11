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

    static func matchingApps(_ query: String) -> [LauncherApp] {
        guard !query.isEmpty else { return [] }
        return Array(appsCache.lazy.filter { $0.name.localizedCaseInsensitiveContains(query) }.prefix(maxResults))
    }

    static func open(_ app: LauncherApp) {
        Logger.info { app.url.path }
        hide()
        if #available(macOS 10.15, *) {
            NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(app.url)
        }
    }

    private static func refreshAppsCacheAsync() {
        DispatchQueue.global(qos: .userInteractive).async {
            let apps = scanApplicationsFolders()
            DispatchQueue.main.async {
                appsCache = apps
                if LauncherPanel.shared.isVisible {
                    LauncherPanel.shared.updateResults()
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
                    apps.append(LauncherApp(url: url, name: url.deletingPathExtension().lastPathComponent))
                    enumerator.skipDescendants()
                } else if enumerator.level >= 2 {
                    enumerator.skipDescendants()
                }
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

struct LauncherApp {
    let url: URL
    let name: String
}
