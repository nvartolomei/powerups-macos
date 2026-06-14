import Cocoa

class Menubar {
    static var statusItem: NSStatusItem!
    static var menu: NSMenu!
    private static let menuDelegate = MenubarMenuDelegate()

    // transparent stand-in so icon-less items keep their text aligned with the items that have an icon
    private static let blankIcon = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
        NSColor.clear.set()
        rect.fill()
        return true
    }

    @discardableResult
    static func addMenuItem(_ title: String, _ action: Selector, _ keyEquivalent: String, _ symbolName: String?, _ color: NSColor? = nil, _ target: AnyObject? = nil) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: keyEquivalent)
        item.target = target
        if let symbolName {
            item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
            if let color {
                item.image = item.image?.withSymbolConfiguration(.init(paletteColors: [color]))
            }
        } else {
            item.image = blankIcon
        }
        return item
    }

    // shows the configured global shortcut next to a menu item, and lets the open menu match it to
    // close and run the action (see MenubarMenuDelegate, which disables the global hotkey while open).
    static func showShortcut(_ item: NSMenuItem, _ keyId: String, _ holdId: String? = nil) {
        guard let shortcut = Preferences.shortcut(keyId), shortcut.keyCode != .none,
              let characters = shortcut.charactersIgnoringModifiers ?? shortcut.characters, !characters.isEmpty else { return }
        item.keyEquivalent = characters
        var modifiers = shortcut.modifierFlags
        if let holdId, let hold = Preferences.shortcut(holdId) {
            modifiers.formUnion(hold.modifierFlags)
        }
        item.keyEquivalentModifierMask = modifiers
    }

    static func initialize() {
        menu = NSMenu()
        menu.delegate = menuDelegate
        menu.title = App.name // perf: prevent going through expensive code-path within appkit
        addMenuItem(NSLocalizedString("Settings…", comment: "Menubar option"), #selector(App.showSettingsWindow), ",", "gear", nil, App.self)
        menu.addItem(NSMenuItem.separator())
        showShortcut(addMenuItem(NSLocalizedString("Show switcher", comment: "Menubar option"), #selector(App.showUiFromShortcut0), "", nil, nil, App.self), "nextWindowShortcut", "holdShortcut")
        showShortcut(addMenuItem(NSLocalizedString("Show launcher", comment: "Menubar option"), #selector(Launcher.toggle), "", nil, nil, Launcher.self), "launcherShortcut")
        menu.addItem(NSMenuItem.separator())
        addMenuItem(String(format: NSLocalizedString("About %@", comment: "Menubar option. %@ is PowerUps"), App.name), #selector(App.showAboutWindow), "", "info.circle", nil, App.self)
        addMenuItem(NSLocalizedString("Check permissions…", comment: "Menubar option"), #selector(App.checkPermissions), "", nil, nil, App.self)
        addMenuItem(NSLocalizedString("Debug tools", comment: "Menubar option"), #selector(App.showDebugWindow), "", nil, nil, App.self)
        menu.addItem(NSMenuItem.separator())
        addMenuItem(String(format: NSLocalizedString("Quit %@", comment: "Menubar option. %@ is PowerUps"), App.name), #selector(NSApplication.terminate(_:)), "q", "power")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button!.target = self
        statusItem.button!.action = #selector(statusItemOnClick)
        statusItem.button!.sendAction(on: [.leftMouseDown, .rightMouseDown])
    }

    @objc static func statusItemOnClick() {
        // NSApp.currentEvent == nil if the icon is "clicked" through VoiceOver
        if let type = NSApp.currentEvent?.type, type != .leftMouseDown {
            App.showUiFromShortcut0()
        } else if let button = statusItem.button {
            Menubar.menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
        }
    }

    static func menubarIconCallback(_: NSControl?) {
        guard Preferences.menubarIconShown else {
            statusItem.isVisible = false
            return
        }
        loadIcon()
    }

    static private func loadIcon() {
        let image = boltImage()
        image.isTemplate = true
        statusItem.button!.image = image
        statusItem.isVisible = true
        statusItem.button!.imageScaling = .scaleProportionallyUpOrDown
    }

    static private func boltImage() -> NSImage {
        let points = [(13.6, 3.5), (6.6, 11.6), (10.4, 11.6), (8.4, 18.5), (15.4, 10.4), (11.6, 10.4)]
        return NSImage(size: NSSize(width: 22, height: 22), flipped: true) { _ in
            let path = NSBezierPath()
            path.move(to: NSPoint(x: points[0].0, y: points[0].1))
            points.dropFirst().forEach { path.line(to: NSPoint(x: $0.0, y: $0.1)) }
            path.close()
            NSColor.black.setFill()
            path.fill()
            return true
        }
    }
}

private class MenubarMenuDelegate: NSObject, NSMenuDelegate {
    private var didDisableGlobalShortcuts = false

    // while the menu's modal tracking loop is open, a registered global hotkey is intercepted at the
    // system level and its action is deferred until the menu closes. disabling the global hotkeys lets
    // the menu's own key equivalents handle the keystroke instead: it closes and runs the action at once.
    func menuWillOpen(_ menu: NSMenu) {
        guard !KeyboardEvents.globalShortcutsAreDisabled else { return }
        didDisableGlobalShortcuts = true
        KeyboardEvents.toggleGlobalShortcuts(true)
    }

    func menuDidClose(_ menu: NSMenu) {
        guard didDisableGlobalShortcuts else { return }
        didDisableGlobalShortcuts = false
        KeyboardEvents.toggleGlobalShortcuts(false)
    }
}
