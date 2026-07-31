import Foundation

/// The decisions behind SleepPrevention, kept clear of IOKit so they can be unit-tested.
class SleepPreventionTestable {
    static let minMinutes = 1
    /// a ceiling only so a typo can't ask for a century; the echoed end time makes any clamping visible
    static let maxMinutes = 30 * 24 * 60
    private static let minutesPerDay = 24 * 60
    /// a cutoff of 0 means no cutoff: the session runs until macOS itself puts the Mac to sleep
    static let cutoffOff = 0
    static let minCutoff = 5
    static let maxCutoff = 50
    static let cutoffStep = 5
    /// one tick per step, both ends included; the two cutoff sliders have to agree on the grid
    static let cutoffTicks = (maxCutoff - minCutoff) / cutoffStep + 1
    static let defaultCutoff = 10

    /// only applies on battery: while plugged in, the charge level says nothing about how long we can stay awake
    static func batteryStops(_ cutoff: Int, _ percent: Int?, _ onBattery: Bool) -> Bool {
        guard cutoff > cutoffOff, onBattery, let percent else { return false }
        return percent <= cutoff
    }

    static func clampMinutes(_ minutes: Int) -> Int {
        min(maxMinutes, max(minMinutes, minutes))
    }

    /// anything at or below 0 is "no cutoff"; a real cutoff stays within what the slider can express
    static func clampCutoff(_ cutoff: Int) -> Int {
        guard cutoff > cutoffOff else { return cutoffOff }
        return min(maxCutoff, max(minCutoff, cutoff))
    }

    /// rounds up, so a 30 minute session reads "30m" rather than "29m" a moment after it starts
    static func remaining(_ seconds: Double) -> String {
        formatDuration(max(1, Int(ceil(seconds / 60))))
    }

    static func formatDuration(_ minutes: Int) -> String {
        let parts = [(minutes / minutesPerDay, "d"), (minutes % minutesPerDay / 60, "h"), (minutes % 60, "m")]
        let written = parts.filter { $0.0 > 0 }.map { "\($0.0)\($0.1)" }
        return written.isEmpty ? "0m" : written.joined(separator: " ")
    }

    /// "90", "45m", "2h", "1h30", "1h 30m", "3d", "2d 6h" all work; anything else is nil, so the field keeps its text
    static func parseDuration(_ text: String) -> Int? {
        var rest = Substring(text.lowercased().filter { !$0.isWhitespace })
        guard !rest.isEmpty else { return nil }
        var minutes = 0
        var matched = false
        for (mark, scale) in [("d", minutesPerDay), ("h", 60)] {
            guard let markIndex = rest.firstIndex(of: Character(mark)) else { continue }
            guard let value = digits(rest[rest.startIndex..<markIndex]) else { return nil }
            minutes += value * scale
            matched = true
            rest = rest[rest.index(after: markIndex)...]
        }
        if rest.hasSuffix("m") {
            rest = rest.dropLast()
        }
        if !rest.isEmpty {
            guard let bareMinutes = digits(rest) else { return nil }
            minutes += bareMinutes
            matched = true
        }
        guard matched else { return nil }
        return clampMinutes(minutes)
    }

    /// 0 when a session ends today, 1 tomorrow, and so on: past tomorrow, saying the time alone isn't enough
    static func daysAhead(_ end: Date, _ now: Date, _ calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: end)).day ?? 0
    }

    /// plain digits only, so "-5" and "1e3" are rejected rather than quietly clamped
    private static func digits(_ text: Substring) -> Int? {
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(text)
    }
}
