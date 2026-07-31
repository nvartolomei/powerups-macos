import Foundation
import IOKit.pwr_mgt

/// Keeps the Mac awake, à la Caffeine, until the session's deadline passes, the user stops it, or the battery
/// reaches the cutoff. Sleep the user asks for (Apple menu, closing the lid) still happens: IOKit assertions
/// only hold off idle sleep.
class SleepPrevention {
    /// both kinds: the display assertion alone lets the Mac sleep, the system one alone lets the screen go dark
    private static let assertionTypes = [kIOPMAssertionTypePreventUserIdleSystemSleep, kIOPMAssertionTypePreventUserIdleDisplaySleep]
    static let presetMinutes = 30
    private static var assertions = [IOPMAssertionID]()
    private static var expiry: Timer?
    /// nil for a session that runs until it is stopped by hand
    private static var deadline: Date?
    private static var batteryCutoff = SleepPreventionTestable.cutoffOff
    /// the running session was started by the power cable, so unplugging is what ends it
    private static var startedByPower = false
    /// "Allow sleep" with the cable in has to stick, or the plugged-in policy would switch it straight back on
    private static var powerSuppressed = false
    /// set by Menubar, so sessions started from anywhere refresh the menu item and the status icon
    static var onChange: (() -> Void)?

    /// power notifications are watched for the whole run: they drive both the battery cutoff and the plugged-in policy
    static func initialize() {
        PowerSource.observe(powerSourceChanged)
        refreshPowerPolicy()
    }

    /// a session that ran out is over even if our timer hasn't fired yet, which it won't have after a system sleep
    static var isActive: Bool {
        guard !assertions.isEmpty else { return false }
        guard let deadline else { return true }
        return deadline > Date()
    }

    static var remaining: String? {
        guard isActive, let deadline else { return nil }
        return SleepPreventionTestable.remaining(deadline.timeIntervalSinceNow)
    }

    /// the cutoff from Settings; the custom prompt can override it for the one session it starts
    static var configuredCutoff: Int {
        guard Preferences.preventSleepBatteryCutoffEnabled else { return SleepPreventionTestable.cutoffOff }
        return SleepPreventionTestable.clampCutoff(Preferences.preventSleepBatteryCutoff)
    }

    /// the battery percentage that would end a session with this cutoff the moment it started, if any
    static func batteryBlocking(_ cutoff: Int) -> Int? {
        let state = PowerSource.state()
        guard SleepPreventionTestable.batteryStops(cutoff, state.percent, state.onBattery) else { return nil }
        return state.percent
    }

    static func start(_ minutes: Int?, _ cutoff: Int, byPower: Bool = false) {
        release()
        batteryCutoff = cutoff
        startedByPower = byPower
        deadline = minutes.map { Date(timeIntervalSinceNow: Double($0) * 60) }
        assertions = assertionTypes.compactMap { assertion($0, minutes) }
        guard !assertions.isEmpty else {
            Logger.error { "could not create the sleep assertions" }
            deadline = nil
            onChange?()
            return
        }
        scheduleExpiry()
        Logger.info { "preventing sleep for \(minutes.map { "\($0)m" } ?? (byPower ? "as long as it is plugged in" : "as long as it takes")), cutoff \(cutoff)%" }
        onChange?()
    }

    static func stop() {
        // the user asking for sleep outranks the plugged-in policy, until the cable moves
        powerSuppressed = !PowerSource.state().onBattery
        end()
    }

    private static func end() {
        guard !assertions.isEmpty else { return }
        release()
        Logger.info { "sleep is allowed again" }
        onChange?()
    }

    private static func release() {
        assertions.forEach { IOPMAssertionRelease($0) }
        assertions = []
        deadline = nil
        startedByPower = false
        expiry?.invalidate()
        expiry = nil
    }

    /// the kernel-side timeout is the backstop: it releases the assertion on time even if our own timer runs late
    private static func assertion(_ type: String, _ minutes: Int?) -> IOPMAssertionID? {
        var properties: [String: Any] = [
            kIOPMAssertionTypeKey: type,
            kIOPMAssertionNameKey: App.name,
            kIOPMAssertionLevelKey: kIOPMAssertionLevelOn,
        ]
        if let minutes {
            properties[kIOPMAssertionTimeoutKey] = Double(minutes) * 60
            properties[kIOPMAssertionTimeoutActionKey] = kIOPMAssertionTimeoutActionRelease
        }
        var id = IOPMAssertionID(0)
        guard IOPMAssertionCreateWithProperties(properties as CFDictionary, &id) == kIOReturnSuccess else { return nil }
        return id
    }

    /// .common so the session still ends while a menu is open
    private static func scheduleExpiry() {
        guard let deadline else { return }
        let timer = Timer(fire: deadline, interval: 0, repeats: false) { _ in expired() }
        RunLoop.main.add(timer, forMode: .common)
        expiry = timer
    }

    private static func expired() {
        guard !isActive else {
            scheduleExpiry()
            return
        }
        end()
        // a timed session that runs out while plugged in hands back to the standing policy
        refreshPowerPolicy()
    }

    private static func powerSourceChanged() {
        batteryChanged()
        refreshPowerPolicy()
    }

    private static func batteryChanged() {
        guard isActive else { return }
        let state = PowerSource.state()
        guard SleepPreventionTestable.batteryStops(batteryCutoff, state.percent, state.onBattery) else { return }
        Logger.info { "battery down to \(state.percent!)%, at the \(batteryCutoff)% cutoff" }
        end()
    }

    /// Settings' "Stay awake while plugged in": the cable starts a session, unplugging or turning the setting off ends it.
    /// A session the user started by hand outranks it, and is left alone here.
    static func refreshPowerPolicy() {
        let onPower = !PowerSource.state().onBattery
        if !onPower {
            powerSuppressed = false
        }
        if startedByPower && (!onPower || !Preferences.preventSleepWhilePluggedIn) {
            end()
            return
        }
        guard onPower, Preferences.preventSleepWhilePluggedIn, !powerSuppressed, !isActive else { return }
        start(nil, SleepPreventionTestable.cutoffOff, byPower: true)
    }
}
