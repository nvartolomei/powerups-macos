import Cocoa

/// built-in commands ranked like apps by hump/prefix of their visible name, e.g. "ls" → Output: LSX, "dar" → Switch to Dark Mode
class LauncherCommands {
    static let all = [
        LauncherCommand(NSLocalizedString("Switch to Dark Mode", comment: ""), { SLSSetAppearanceThemeLegacy(true) }, icon: LauncherCommand.symbolIcon("moon.fill")),
        LauncherCommand(NSLocalizedString("Switch to Light Mode", comment: ""), { SLSSetAppearanceThemeLegacy(false) }, icon: LauncherCommand.symbolIcon("sun.max.fill")),
        LauncherCommand(NSLocalizedString("Output: LSX", comment: ""), { AudioOutput.route(to: "LSX") }, icon: LauncherCommand.symbolIcon("airplayaudio")),
        LauncherCommand(NSLocalizedString("Output: AirPods", comment: ""), { AudioOutput.route(to: "AirPods") }, icon: LauncherCommand.symbolIcon("airpods")),
        LauncherCommand(NSLocalizedString("Output: MacBook Speakers", comment: ""), { AudioOutput.route(to: "MacBook") }, icon: LauncherCommand.symbolIcon("speaker.wave.2.fill")),
    ]
}

struct LauncherCommand: LauncherSearchable {
    /// referenced from the background queue that scans apps, as cold icon loads hit the disk
    static let icon = NSWorkspace.shared.icon(forFile: NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences")?.path ?? "/System/Applications/System Settings.app")
    let name: String
    let icon: NSImage
    let action: () -> Void
    /// hump words and lowercased text are derived from the visible name, exactly like an app (see LauncherSearchable)
    let lowercasedName: String
    let words: [[Character]]

    init(_ name: String, _ action: @escaping () -> Void, icon: NSImage = LauncherCommand.icon) {
        self.name = name
        self.icon = icon
        self.action = action
        lowercasedName = name.lowercased()
        words = LauncherSearch.humpWords(name)
    }

    /// an SF Symbol rendered as a template image, so it tints to the launcher's appearance-following label color
    static func symbolIcon(_ name: String) -> NSImage {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 22, weight: .regular)) else { return icon }
        image.isTemplate = true
        return image
    }
}
