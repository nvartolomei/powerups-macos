import Cocoa

/// built-in commands matched by typing a prefix of their keyword (3+ characters), e.g. "dar" → Switch to Dark Mode
class LauncherCommands {
    private static let minQueryLength = 3
    private static let all = [
        LauncherCommand("dark", NSLocalizedString("Switch to Dark Mode", comment: ""), { SLSSetAppearanceThemeLegacy(true) }),
        LauncherCommand("light", NSLocalizedString("Switch to Light Mode", comment: ""), { SLSSetAppearanceThemeLegacy(false) }),
    ]

    static func matching(_ query: String) -> [LauncherCommand] {
        let normalized = String(LauncherSearch.normalizedQuery(query))
        guard normalized.count >= minQueryLength else { return [] }
        return all.filter { $0.keyword.hasPrefix(normalized) }
    }
}

struct LauncherCommand {
    /// referenced from the background queue that scans apps, as cold icon loads hit the disk
    static let icon = NSWorkspace.shared.icon(forFile: NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences")?.path ?? "/System/Applications/System Settings.app")
    let keyword: String
    let name: String
    let action: () -> Void

    init(_ keyword: String, _ name: String, _ action: @escaping () -> Void) {
        self.keyword = keyword
        self.name = name
        self.action = action
    }
}
