import Cocoa

/// built-in commands matched by typing a prefix of their keyword (3+ characters), e.g. "dar" → Switch to Dark Mode
class LauncherCommands {
    private static let minQueryLength = 3
    private static let all = [
        LauncherCommand("dark", NSLocalizedString("Switch to Dark Mode", comment: ""), { SLSSetAppearanceThemeLegacy(true) }, icon: LauncherCommand.symbolIcon("moon.fill")),
        LauncherCommand("light", NSLocalizedString("Switch to Light Mode", comment: ""), { SLSSetAppearanceThemeLegacy(false) }, icon: LauncherCommand.symbolIcon("sun.max.fill")),
        LauncherCommand("lsx", NSLocalizedString("Output: LSX", comment: ""), { AudioOutput.route(to: "LSX") }, icon: LauncherCommand.symbolIcon("airplayaudio")),
        LauncherCommand("airpods", NSLocalizedString("Output: AirPods", comment: ""), { AudioOutput.route(to: "AirPods") }, icon: LauncherCommand.symbolIcon("airpods")),
        LauncherCommand("speakers", NSLocalizedString("Output: MacBook Speakers", comment: ""), { AudioOutput.route(to: "MacBook") }, icon: LauncherCommand.symbolIcon("speaker.wave.2.fill")),
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
    let icon: NSImage
    let action: () -> Void

    init(_ keyword: String, _ name: String, _ action: @escaping () -> Void, icon: NSImage = LauncherCommand.icon) {
        self.keyword = keyword
        self.name = name
        self.icon = icon
        self.action = action
    }

    /// an SF Symbol rendered as a template image, so it tints to the launcher's appearance-following label color
    static func symbolIcon(_ name: String) -> NSImage {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 22, weight: .regular)) else { return icon }
        image.isTemplate = true
        return image
    }
}
