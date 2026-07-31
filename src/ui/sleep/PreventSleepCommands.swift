import Cocoa

/// The user-facing entry points into SleepPrevention: what the menu bar items, the launcher commands and the
/// prompt call. It also owns the one question a session can raise, so the logic layer never puts up a dialog.
class PreventSleepCommands {
    @objc static func toggle() {
        if SleepPrevention.isActive {
            SleepPrevention.stop()
        } else {
            start(nil, SleepPrevention.configuredCutoff)
        }
    }

    @objc static func startPreset() {
        start(SleepPrevention.presetMinutes, SleepPrevention.configuredCutoff)
    }

    @objc static func stop() {
        SleepPrevention.stop()
    }

    /// a battery already at the cutoff would end the session as soon as it started; offer to drop the cutoff instead
    static func start(_ minutes: Int?, _ cutoff: Int) {
        guard let percent = SleepPrevention.batteryBlocking(cutoff) else {
            SleepPrevention.start(minutes, cutoff)
            return
        }
        askToStartBelowCutoff(minutes, cutoff, percent)
    }

    private static func askToStartBelowCutoff(_ minutes: Int?, _ cutoff: Int, _ percent: Int) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("The battery is too low", comment: "Sleep prevention alert")
        alert.informativeText = String(format: NSLocalizedString("The battery is at %d%%, at or below the %d%% cutoff, so the session would end as soon as it started.", comment: "Sleep prevention alert"), percent, cutoff)
        alert.addButton(withTitle: NSLocalizedString("Prevent sleep anyway", comment: "Sleep prevention alert"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Sleep prevention alert"))
        App.shared.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        SleepPrevention.start(minutes, SleepPreventionTestable.cutoffOff)
    }
}
