import Foundation
import IOKit.ps

/// The internal battery, read on demand and watched through IOKit's power-source notifications rather than polled.
class PowerSource {
    /// desktops have no internal battery: percent is nil there, and the battery cutoff never trips
    struct State {
        let percent: Int?
        let onBattery: Bool
    }

    private static let noBattery = State(percent: nil, onBattery: false)
    /// IOKit passes the callback no context of ours, so the handler is stored here instead of captured
    private static var handler: (() -> Void)?
    /// reading it costs a round trip to powerd, and it can only change when IOKit says so
    private static var cached: State?

    /// commonModes, so a change still lands while a menu is being tracked
    static func observe(_ newHandler: @escaping () -> Void) {
        handler = newHandler
        guard let source = IOPSNotificationCreateRunLoopSource({ _ in PowerSource.changed() }, nil)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        cached = read()
    }

    static func state() -> State {
        if let cached { return cached }
        cached = read()
        return cached!
    }

    private static func changed() {
        cached = read()
        handler?()
    }

    private static func read() -> State {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return noBattery }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            return State(percent: percent(description), onBattery: description[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue)
        }
        return noBattery
    }

    private static func percent(_ description: [String: Any]) -> Int? {
        guard let current = description[kIOPSCurrentCapacityKey] as? Int,
              let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { return nil }
        return Int((Double(current) / Double(maximum) * 100).rounded())
    }
}
