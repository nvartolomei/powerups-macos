import Cocoa
import UniformTypeIdentifiers

class GeneralTab {
    private static var menubarIsVisibleObserver: NSKeyValueObservation?

    static func initTab() -> NSView {
        let startAtLogin = TableGroupView.Row(leftTitle: NSLocalizedString("Start at login", comment: ""),
            rightViews: [LabelAndControl.makeSwitch("startAtLogin")])
        let menuIconShownToggle = LabelAndControl.makeSwitch("menubarIconShown")
        let menubarIcon = TableGroupView.Row(leftTitle: NSLocalizedString("Menubar icon", comment: ""),
            rightViews: [menuIconShownToggle])
        enableDraggingOffMenubarIcon(menuIconShownToggle)
        let table = TableGroupView(width: SettingsWindow.contentWidth)
        table.addRow(startAtLogin)
        table.addRow(menubarIcon)
        addBatteryCutoffRows(table)
        let exportButton = NSButton(title: NSLocalizedString("Export settings…", comment: ""), target: nil, action: nil)
        exportButton.onAction = { _ in exportSettings() }
        let importButton = NSButton(title: NSLocalizedString("Import settings…", comment: ""), target: nil, action: nil)
        importButton.onAction = { _ in importSettings() }
        let tools = StackView([exportButton, importButton], .horizontal)
        let view = TableGroupSetView(originalViews: [table, tools], bottomPadding: 0)
        return view
    }

    static func refreshControlsFromPreferences() {}

    /// the standing policy for every sleep-prevention session; the "Custom…" prompt starts from it and can
    /// override it for the one session it launches
    private static func addBatteryCutoffRows(_ table: TableGroupView) {
        table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Awake while plugged in", comment: ""),
                                        subTitle: NSLocalizedString("Holds sleep off the whole time the power adapter is connected", comment: ""),
                                        rightViews: [LabelAndControl.makeSwitch("preventSleepWhilePluggedIn")]))
        let levelViews = LabelAndControl.makeLabelWithSlider("", "preventSleepBatteryCutoff",
                                                             Double(SleepPreventionTestable.minCutoff),
                                                             Double(SleepPreventionTestable.maxCutoff),
                                                             SleepPreventionTestable.cutoffTicks,
                                                             true, "%", width: 180)
        let enableLevel = { (on: Bool) in levelViews.forEach { ($0 as? NSControl)?.isEnabled = on } }
        let toggle = LabelAndControl.makeSwitch("preventSleepBatteryCutoffEnabled", extraAction: { sender in
            enableLevel((sender as? Switch)?.state == .on)
        })
        table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Let the Mac sleep on low battery", comment: ""),
                                        subTitle: NSLocalizedString("Ends a “Prevent sleep” session before the battery runs out", comment: ""),
                                        rightViews: [toggle]))
        table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Battery level", comment: ""), rightViews: levelViews))
        enableLevel(Preferences.preventSleepBatteryCutoffEnabled)
    }

    private static func enableDraggingOffMenubarIcon(_ menuIconShownToggle: Switch) {
        Menubar.statusItem.behavior = .removalAllowed
        menubarIsVisibleObserver = Menubar.statusItem.observe(\.isVisible, options: [.old, .new]) { _, change in
            Logger.debug { "---- \(change)" }
            if change.oldValue == true && change.newValue == false {
                menuIconShownToggle.state = .off
                LabelAndControl.controlWasChanged(menuIconShownToggle, nil)
            }
        }
    }

    @objc static func resetPreferences() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = ""
        alert.informativeText = NSLocalizedString("You can’t undo this action.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        let resetButton = alert.addButton(withTitle: NSLocalizedString("Reset settings and restart", comment: ""))
        resetButton.hasDestructiveAction = true
        if alert.runModal() == .alertSecondButtonReturn {
            Preferences.resetAll()
            App.restart()
        }
    }

    private static func exportSettings() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(App.bundleIdentifier).plist"
        panel.allowedContentTypes = [.propertyList]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        NSDictionary(dictionary: Preferences.all).write(to: url, atomically: true)
    }

    private static func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.propertyList]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let dict = NSDictionary(contentsOf: url) as? [String: Any] else {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = NSLocalizedString("Failed to import settings", comment: "")
            alert.runModal()
            return
        }
        UserDefaults.standard.setPersistentDomain(dict, forName: App.bundleIdentifier)
        CachedUserDefaults.cache.withLock { $0.removeAll() }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = NSLocalizedString("Settings imported", comment: "")
        alert.informativeText = NSLocalizedString("The application needs to restart to apply the imported settings.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Restart Now", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Later", comment: ""))
        if alert.runModal() == .alertFirstButtonReturn {
            App.restart()
        }
    }

}
