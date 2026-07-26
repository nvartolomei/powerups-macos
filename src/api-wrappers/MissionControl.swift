import Foundation

class MissionControl {
    private static let stateLock = NSLock()
    private static var state_ = MissionControlState.inactive

    static func state() -> MissionControlState {
        stateLock.lock()
        defer { stateLock.unlock() }
        return state_
    }

    static func setState(_ state: MissionControlState) {
        stateLock.lock()
        defer { stateLock.unlock() }
        state_ = state
        Logger.info { state }
    }

    // on macOS < 12, this is the way we used to guess if Mission Control is active
}
