import Cocoa
import SQLite3

/// recently opened folders from VS Code's "Open Recent" list, surfaced in the launcher and reopened through the `code` CLI
/// source: ~/.vscode-shared/sharedStorage/state.vscdb, key history.recentlyOpenedPathsList (the APPLICATION_SHARED storage scope)
class LauncherVSCodeRecents {
    static let maxRecents = 10
    static var all = [LauncherRecent]()
    private static let bundleId = "com.microsoft.VSCode"
    /// the shared-data folder is named after product.json's sharedDataFolderName; ".vscode-shared" is VS Code stable
    private static let dbURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".vscode-shared/sharedStorage/state.vscdb")

    /// called on the apps-scan background queue: the SQLite read and cold icon load both hit the disk
    static func load() -> [LauncherRecent] {
        guard let json = readRecentsJSON(),
              let recents = try? JSONDecoder().decode(StoredRecents.self, from: json) else { return [] }
        let icon = appIcon()
        var folders = [LauncherRecent]()
        for entry in recents.entries {
            guard let folder = entry.folder, isPresent(folder.uri) else { continue }
            folders.append(LauncherRecent(folder, icon))
            if folders.count == maxRecents { break }
        }
        return folders
    }

    static func open(_ recent: LauncherRecent, then completion: @escaping () -> Void) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId), let cli = cliURL(appURL) else { completion(); return }
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = cli
            process.arguments = ["--folder-uri", recent.folderUri]
            try? process.run()
            process.waitUntilExit()
            // the code CLI hands the open to the already-running VS Code over IPC; as an LSUIElement accessory we never
            // become frontmost, so we activate VS Code the way we open apps. completion fires once it is active, so the
            // launcher can keep a spinner up for the whole round-trip instead of vanishing into a blank half-second
            DispatchQueue.main.async {
                NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration()) { _, _ in
                    DispatchQueue.main.async(execute: completion)
                }
            }
        }
    }

    private static func readRecentsJSON() -> Data? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { sqlite3_close(db); return nil }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM ItemTable WHERE key = 'history.recentlyOpenedPathsList'", -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { return nil }
        return Data(String(cString: text).utf8)
    }

    /// local folders that no longer exist are dropped; remote folders can't be probed without connecting, so they stay
    private static func isPresent(_ uri: String) -> Bool {
        guard let url = URL(string: uri), url.scheme == "file" else { return true }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private static func appIcon() -> NSImage {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            let folder = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil) ?? NSImage()
            folder.isTemplate = true
            return folder
        }
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }

    private static func cliURL(_ appURL: URL) -> URL? {
        let cli = appURL.appendingPathComponent("Contents/Resources/app/bin/code")
        return FileManager.default.isExecutableFile(atPath: cli.path) ? cli : nil
    }
}

private struct StoredRecents: Decodable {
    let entries: [StoredEntry]
}

private struct StoredEntry: Decodable {
    let folderUri: String?
    let label: String?
    let remoteAuthority: String?
    /// entries without a folderUri are recent files or workspaces, which the launcher doesn't surface
    var folder: RecentFolder? {
        guard let folderUri else { return nil }
        return RecentFolder(uri: folderUri, label: label, remoteAuthority: remoteAuthority)
    }
}

struct RecentFolder {
    let uri: String
    let label: String?
    let remoteAuthority: String?
}

struct LauncherRecent: LauncherSearchable {
    let folderUri: String
    let name: String
    let lowercasedName: String
    let words: [[Character]]
    let icon: NSImage

    init(_ folder: RecentFolder, _ icon: NSImage) {
        folderUri = folder.uri
        name = "VSCode: " + LauncherRecent.displayPath(folder)
        // search the whole visible label, exactly like an app or command, so "vsc redpanda" narrows to the VS Code recents
        lowercasedName = name.lowercased()
        words = LauncherSearch.humpWords(name)
        self.icon = icon
    }

    /// "~/redpanda [SSH: nv-dev]" for remotes (VS Code already stores that as the label), a home-relative path for local folders
    private static func displayPath(_ folder: RecentFolder) -> String {
        if let label = folder.label, !label.isEmpty { return label }
        let raw = URL(string: folder.uri)?.path.removingPercentEncoding ?? folder.uri
        let path = abbreviateHome(raw)
        guard let remote = remoteName(folder.remoteAuthority) else { return path }
        return "\(path) [SSH: \(remote)]"
    }

    private static func abbreviateHome(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private static func remoteName(_ authority: String?) -> String? {
        guard let authority else { return nil }
        let prefix = "ssh-remote+"
        return authority.hasPrefix(prefix) ? String(authority.dropFirst(prefix.count)) : authority
    }
}
