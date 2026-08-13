import Cocoa

/// evaluates the launcher query as an arithmetic expression: + - * / %, power as ^ or **, left shift as <<,
/// parentheses, unary minus, decimals, and basic functions like sqrt(2); ln is natural log, log is base 10
/// unit suffixes multiply into base units (bytes, seconds): "5GiB" is 5368709120, "90min" is 5400
/// a trailing standalone "in <unit>" or "to <unit>" divides back out: "3<<30 in MiB" is "3,072 MiB", and
/// "in date"/"in utc"/"in local" read the result as a unix timestamp ("1786613400 in utc" is a date)
/// queries without an operator (plain numbers, app names) are not expressions, so they fall through to app search
/// expressions being typed evaluate their complete part: "sin(42)*", "sin(42)*sq", and "sin(42" all evaluate "sin(42)"
class LauncherCalculator {
    /// referenced from the background queue that scans apps, as cold icon loads hit the disk
    static let icon = NSWorkspace.shared.icon(forFile: NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.calculator")?.path ?? "/System/Applications/Calculator.app")
    private static let functions: [String: (Double) -> Double] = [
        "sqrt": sqrt, "cbrt": cbrt, "abs": abs, "exp": exp, "ln": log, "log": log10, "log2": log2,
        "sin": sin, "cos": cos, "tan": tan, "floor": floor, "ceil": ceil, "round": round,
    ]
    /// spellings are matched case-insensitively and map to bytes or seconds; KB/MB/… are decimal like Finder,
    /// KiB/MiB/… binary, and kbit/mbit/… divide by 8 so throughput math works ("10GiB / 1gbit in s")
    /// bare K/M/G/T are rejected (JEDEC reads them binary, SI decimal) and minutes are "min", not "m",
    /// so a dd-style "5M" falls through to app search instead of quietly meaning 5 minutes
    private static let units: [String: Unit] = [
        "b": Unit("B", 1), "kb": Unit("KB", 1e3), "mb": Unit("MB", 1e6), "gb": Unit("GB", 1e9), "tb": Unit("TB", 1e12), "pb": Unit("PB", 1e15),
        "kib": Unit("KiB", 1024), "mib": Unit("MiB", 1_048_576), "gib": Unit("GiB", 1_073_741_824), "tib": Unit("TiB", 1_099_511_627_776), "pib": Unit("PiB", 1_125_899_906_842_624),
        "bit": Unit("bit", 0.125), "kbit": Unit("kbit", 125), "mbit": Unit("mbit", 125_000), "gbit": Unit("gbit", 125_000_000), "tbit": Unit("tbit", 125_000_000_000),
        "ns": Unit("ns", 1e-9), "us": Unit("µs", 1e-6), "µs": Unit("µs", 1e-6), "ms": Unit("ms", 1e-3),
        "s": Unit("s", 1), "min": Unit("min", 60), "h": Unit("h", 3600), "hr": Unit("h", 3600), "d": Unit("d", 86400), "w": Unit("w", 604_800),
    ]
    private static let utc = TimeZone(identifier: "UTC")!

    private struct Unit {
        let canonical: String
        let value: Double

        init(_ canonical: String, _ value: Double) {
            self.canonical = canonical
            self.value = value
        }
    }

    private enum Target {
        case unit(Unit)
        case timestamp(TimeZone)
    }

    private struct Conversion {
        let keyword: String
        let label: String
        let target: Target
    }

    static func evaluate(_ query: String) -> LauncherCalculation? {
        let (expression, conversion) = splitConversion(query)
        let original = Array(expression.filter { !$0.isWhitespace })
        guard qualifies(original, conversion != nil) else { return nil }
        var chars = original
        while !chars.isEmpty {
            let completed = chars + [Character](repeating: ")", count: unclosedParens(chars))
            var parser = Parser(completed)
            if let value = parser.parseToEnd() { return calculation(completed, value, conversion) }
            guard trimIncompleteTail(&chars) else { return nil }
        }
        return nil
    }

    /// a pasted unix timestamp (10 digits, or 13 with milliseconds) gets a passive date row without any syntax
    /// only years 2001–2100 qualify, so most 10-digit numbers that are not timestamps (phone numbers, ids) stay quiet
    static func timestamp(_ query: String) -> LauncherCalculation? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 10 || trimmed.count == 13, trimmed.allSatisfy(\.isNumber), let value = Double(trimmed) else { return nil }
        let seconds = trimmed.count == 13 ? value / 1000 : value
        guard seconds >= 978_307_200, seconds < 4_133_980_800 else { return nil }
        return LauncherCalculation(evaluatedExpression: trimmed, display: dateDisplay(seconds, utc), raw: dateRaw(seconds, utc))
    }

    /// the conversion keyword must be a standalone word, so only the last whitespace-delimited "in"/"to" splits
    /// the query; the expression side still strips its whitespace, so "5 GiB in MB" and "5GiB in MB" both work
    /// a trailing partial keyword or unit ("3<<30 i", "3<<30 in Mi") evaluates just the expression while typing
    private static func splitConversion(_ query: String) -> (String, Conversion?) {
        let words = query.split(whereSeparator: \.isWhitespace)
        guard let k = words.lastIndex(where: { keyword($0) != nil }), k >= 1 else { return (trimPartialKeyword(words) ?? query, nil) }
        let expression = words[..<k].joined(separator: " ")
        let tail = words[(k + 1)...]
        guard let word = tail.first?.lowercased() else { return (expression, nil) }
        guard tail.count == 1 else { return (query, nil) }
        guard let (label, target) = target(word) else { return (isTargetPrefix(word) ? expression : query, nil) }
        return (expression, Conversion(keyword: keyword(words[k])!, label: label, target: target))
    }

    private static func keyword(_ word: Substring) -> String? {
        let lowered = word.lowercased()
        return lowered == "in" || lowered == "to" ? lowered : nil
    }

    private static func trimPartialKeyword(_ words: [Substring]) -> String? {
        guard words.count >= 2, let last = words.last?.lowercased(), last == "i" || last == "t" else { return nil }
        return words.dropLast().joined(separator: " ")
    }

    private static func target(_ word: String) -> (String, Target)? {
        if word == "date" || word == "utc" { return (word, .timestamp(utc)) }
        if word == "local" { return (word, .timestamp(.current)) }
        return units[word].map { ($0.canonical, .unit($0)) }
    }

    private static func isTargetPrefix(_ word: String) -> Bool {
        units.keys.contains { $0.hasPrefix(word) } || ["date", "utc", "local"].contains { $0.hasPrefix(word) }
    }

    /// plain numbers and app names must fall through to app search: an expression needs an operator,
    /// a unit suffix ("5GiB"), or a complete conversion target ("4096 in KiB")
    private static func qualifies(_ chars: [Character], _ hasConversion: Bool) -> Bool {
        if hasConversion || chars.contains(where: { "+-*/%^()<".contains($0) }) { return true }
        var i = 0
        while i < chars.count, chars[i].isNumber || chars[i] == "." { i += 1 }
        guard i > 0, i < chars.count else { return false }
        return units[String(chars[i...]).lowercased()] != nil
    }

    private static func unclosedParens(_ chars: [Character]) -> Int {
        var depth = 0
        for c in chars {
            if c == "(" { depth += 1 }
            if c == ")" && depth > 0 { depth -= 1 }
        }
        return depth
    }

    /// an expression being typed ends with an operator, an open paren, or a partial function or unit name
    /// dropping that tail evaluates the complete part, so the result doesn't flicker off mid-typing
    /// anything else (e.g. "1+password") is not an expression being typed, so it falls through to app search
    private static func trimIncompleteTail(_ chars: inout [Character]) -> Bool {
        guard let last = chars.last else { return false }
        if "+-*/%^.(<".contains(last) {
            chars.removeLast()
            return true
        }
        guard last.isLetter || last.isNumber else { return false }
        var start = chars.count
        while start > 0 && (chars[start - 1].isLetter || chars[start - 1].isNumber) { start -= 1 }
        while start < chars.count && chars[start].isNumber { start += 1 }
        guard start < chars.count, prefixesFunctionOrUnit(String(chars[start...])) else { return false }
        chars.removeSubrange(start...)
        return true
    }

    private static func prefixesFunctionOrUnit(_ run: String) -> Bool {
        guard !functions.keys.contains(where: { $0.hasPrefix(run) }) else { return true }
        let lowered = run.lowercased()
        return units.keys.contains { $0.hasPrefix(lowered) }
    }

    /// formats the evaluated expression for the results row: single spaces around binary operators,
    /// none inside parentheses, after a function name, or after a unary sign
    /// e.g. "((42*5)/8+26-sqrt(42*2))" → "((42 * 5) / 8 + 26 - sqrt(42 * 2))"
    private static func formatExpression(_ chars: [Character]) -> String {
        enum Token { case number(String), name(String), binary(String), unary(String), open, close }
        var tokens: [Token] = []
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isNumber || c == "." {
                let start = i
                while i < chars.count, chars[i].isNumber || chars[i] == "." { i += 1 }
                tokens.append(.number(String(chars[start..<i])))
            } else if c.isLetter {
                let start = i
                while i < chars.count, chars[i].isLetter || chars[i].isNumber { i += 1 }
                tokens.append(.name(String(chars[start..<i])))
            } else if c == "(" {
                tokens.append(.open); i += 1
            } else if c == ")" {
                tokens.append(.close); i += 1
            } else if c == "*", i + 1 < chars.count, chars[i + 1] == "*" {
                tokens.append(.binary("**")); i += 2
            } else if c == "<", i + 1 < chars.count, chars[i + 1] == "<" {
                tokens.append(.binary("<<")); i += 2
            } else if c == "+" || c == "-" {
                // a sign is binary only when it follows an operand; otherwise it's a unary that binds to the next operand
                let followsOperand: Bool
                switch tokens.last {
                case .number, .name, .close: followsOperand = true
                default: followsOperand = false
                }
                tokens.append(followsOperand ? .binary(String(c)) : .unary(String(c))); i += 1
            } else {
                tokens.append(.binary(String(c))); i += 1
            }
        }
        // unit spellings echo canonically ("5gib" shows "5 GiB"), so the row confirms how the query was read
        for index in tokens.indices {
            guard case .name(let name) = tokens[index], let unit = units[name.lowercased()] else { continue }
            if index + 1 < tokens.count, case .open = tokens[index + 1] { continue }
            tokens[index] = .name(unit.canonical)
        }
        func text(_ token: Token) -> String {
            switch token {
            case .number(let s), .name(let s), .binary(let s), .unary(let s): return s
            case .open: return "("
            case .close: return ")"
            }
        }
        var result = ""
        for (index, token) in tokens.enumerated() {
            if index > 0 {
                let spaced: Bool
                switch (tokens[index - 1], token) {
                case (.open, _), (_, .close), (.unary, _): spaced = false
                case (.name, .open): spaced = false
                default: spaced = true
                }
                if spaced { result += " " }
            }
            result += text(token)
        }
        return result
    }

    private static func calculation(_ chars: [Character], _ value: Double, _ conversion: Conversion?) -> LauncherCalculation? {
        guard let conversion else {
            return LauncherCalculation(evaluatedExpression: formatExpression(chars), display: displayFormat(value), raw: rawFormat(value))
        }
        let expression = "\(formatExpression(chars)) \(conversion.keyword) \(conversion.label)"
        switch conversion.target {
        case .unit(let unit):
            let converted = value / unit.value
            guard converted.isFinite else { return nil }
            return LauncherCalculation(evaluatedExpression: expression, display: convertedDisplay(converted, unit.canonical), raw: convertedRaw(converted))
        case .timestamp(let timeZone):
            guard let seconds = epochSeconds(value) else { return nil }
            return LauncherCalculation(evaluatedExpression: expression, display: dateDisplay(seconds, timeZone), raw: dateRaw(seconds, timeZone))
        }
    }

    /// raw is what gets copied: machine-formatted, locale-independent
    /// whole numbers print without decimals; %g caps the noise from float arithmetic at 10 significant digits
    private static func rawFormat(_ value: Double) -> String {
        if value.rounded() == value && abs(value) < 1e15 { return String(Int64(value)) }
        return String(format: "%.10g", value)
    }

    /// display is what the results row shows: digit grouping and separators from the user's locale
    static func displayFormat(_ value: Double, _ locale: Locale = .current) -> String {
        guard abs(value) < 1e15 else { return rawFormat(value) }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        if value.rounded() == value { return formatter.string(from: Int64(value) as NSNumber) ?? rawFormat(value) }
        formatter.usesSignificantDigits = true
        formatter.maximumSignificantDigits = 10
        return formatter.string(from: value as NSNumber) ?? rawFormat(value)
    }

    /// converted results keep the fraction that significant-digit formatting would eat:
    /// "1786613400123ms in s" must show ".123" even though the value already has 10 integer digits
    private static func conversionFractionDigits(_ value: Double) -> Int {
        let integerDigits = abs(value) < 1 ? 0 : Int(log10(abs(value))) + 1
        return max(6, 10 - integerDigits)
    }

    static func convertedDisplay(_ value: Double, _ unit: String, _ locale: Locale = .current) -> String {
        guard abs(value) < 1e15, value == 0 || abs(value) >= 1e-6 else { return "\(String(format: "%.10g", value)) \(unit)" }
        if value.rounded() == value { return "\(displayFormat(value, locale)) \(unit)" }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = conversionFractionDigits(value)
        return "\(formatter.string(from: value as NSNumber) ?? convertedRaw(value)) \(unit)"
    }

    static func convertedRaw(_ value: Double) -> String {
        if value.rounded() == value && abs(value) < 1e15 { return String(Int64(value)) }
        guard abs(value) < 1e15, abs(value) >= 1e-6 else { return String(format: "%.10g", value) }
        var digits = String(format: "%.\(conversionFractionDigits(value))f", value)
        while digits.hasSuffix("0") { digits.removeLast() }
        if digits.hasSuffix(".") { digits.removeLast() }
        return digits
    }

    /// real timestamps in seconds and milliseconds live 1000x apart: 1e11 is the year 5138 read as seconds
    /// and March 1973 read as milliseconds, so no real timestamp is ambiguous across that boundary
    /// beyond years 1–9999 a formatted date is garbage rather than an answer, so the conversion fails instead
    private static func epochSeconds(_ value: Double) -> Double? {
        let seconds = abs(value) >= 1e11 ? value / 1000 : value
        guard seconds >= -62_135_596_800, seconds < 253_402_300_800 else { return nil }
        return seconds
    }

    /// a date is never shown without its timezone label, so it can't be misread as some other zone
    static func dateDisplay(_ seconds: Double, _ timeZone: TimeZone, _ locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(hasMilliseconds(seconds) ? "yMMMdjmmssSSS" : "yMMMdjmmss")
        let date = Date(timeIntervalSince1970: seconds)
        return "\(formatter.string(from: date)) \(zoneLabel(timeZone, date))"
    }

    static func dateRaw(_ seconds: Double, _ timeZone: TimeZone) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        if hasMilliseconds(seconds) { formatter.formatOptions.insert(.withFractionalSeconds) }
        return formatter.string(from: Date(timeIntervalSince1970: seconds))
    }

    private static func zoneLabel(_ timeZone: TimeZone, _ date: Date) -> String {
        guard timeZone.secondsFromGMT(for: date) != 0 else { return "UTC" }
        return timeZone.abbreviation(for: date) ?? timeZone.identifier
    }

    private static func hasMilliseconds(_ seconds: Double) -> Bool {
        (seconds * 1000).rounded() != seconds.rounded() * 1000
    }

    /// recursive descent over precedence levels: addition := multiplication (('+'|'-') multiplication)*, etc.
    /// shift binds loosest, as in C, so "1<<2+3" is "1<<5"
    /// unary minus binds looser than power so that "-2^2" is -4; power is right-associative
    /// every intermediate value must be finite: IEEE would quietly give "1/(1/(1-1))" = 1/inf = 0
    private struct Parser {
        private let chars: [Character]
        private var i = 0

        init(_ chars: [Character]) {
            self.chars = chars
        }

        mutating func parseToEnd() -> Double? {
            guard let value = shift(), i == chars.count else { return nil }
            return value
        }

        /// scaling by a power of two instead of shifting an Int64 keeps results exact beyond 63 bits and
        /// lets overflow go non-finite, so "1<<9999" fails like "9^9999"
        /// fractional operands and negative counts are rejected rather than truncated
        private mutating func shift() -> Double? {
            guard var value = addition() else { return nil }
            while peek() == "<", peek(1) == "<" {
                i += 2
                guard let rhs = addition(), value.rounded() == value, rhs.rounded() == rhs, rhs >= 0, let next = finite(value * pow(2, rhs)) else { return nil }
                value = next
            }
            return value
        }

        private mutating func addition() -> Double? {
            guard var value = multiplication() else { return nil }
            while let op = peek(), op == "+" || op == "-" {
                i += 1
                guard let rhs = multiplication(), let next = finite(op == "+" ? value + rhs : value - rhs) else { return nil }
                value = next
            }
            return value
        }

        private mutating func multiplication() -> Double? {
            guard var value = unary() else { return nil }
            while let op = peek(), op == "*" || op == "/" || op == "%" {
                i += 1
                guard let rhs = unary(), let next = finite(multiplicative(value, op, rhs)) else { return nil }
                value = next
            }
            return value
        }

        /// modulo mirrors C fmod: the result takes the sign of the dividend, and a zero divisor yields NaN,
        /// which finite() rejects so "5%0" fails like "5/0"
        private func multiplicative(_ lhs: Double, _ op: Character, _ rhs: Double) -> Double {
            switch op {
            case "*": return lhs * rhs
            case "/": return lhs / rhs
            default: return lhs.truncatingRemainder(dividingBy: rhs)
            }
        }

        private mutating func unary() -> Double? {
            guard peek() == "-" else { return exponentiation() }
            i += 1
            return unary().map { -$0 }
        }

        private mutating func exponentiation() -> Double? {
            guard let base = primary() else { return nil }
            if peek() == "^" {
                i += 1
            } else if peek() == "*" && peek(1) == "*" {
                i += 2
            } else {
                return base
            }
            guard let power = unary() else { return nil }
            return finite(pow(base, power))
        }

        /// a unit suffix is a postfix multiplier into base units, on a number or a closed paren:
        /// "5GiB" is 5368709120 and "(1+2)GiB" works the same way
        private mutating func primary() -> Double? {
            guard let value = operand() else { return nil }
            return unitSuffix(value)
        }

        private mutating func operand() -> Double? {
            if peek() == "(" { return parenthesized() }
            if let c = peek(), c.isLetter { return functionCall() }
            return number()
        }

        private mutating func unitSuffix(_ value: Double) -> Double? {
            let start = i
            while let c = peek(), c.isLetter { i += 1 }
            guard i > start else { return value }
            guard let unit = LauncherCalculator.units[String(chars[start..<i]).lowercased()] else { return nil }
            return finite(value * unit.value)
        }

        private mutating func parenthesized() -> Double? {
            i += 1
            guard let value = shift(), peek() == ")" else { return nil }
            i += 1
            return value
        }

        private mutating func functionCall() -> Double? {
            let start = i
            while let c = peek(), c.isLetter || c.isNumber { i += 1 }
            guard let function = LauncherCalculator.functions[String(chars[start..<i])] else { return nil }
            guard peek() == "(" else { return nil }
            guard let argument = parenthesized() else { return nil }
            return finite(function(argument))
        }

        private mutating func number() -> Double? {
            let start = i
            while let c = peek(), c.isNumber || c == "." { i += 1 }
            guard i > start else { return nil }
            return Double(String(chars[start..<i])).flatMap(finite)
        }

        private func finite(_ value: Double) -> Double? {
            value.isFinite ? value : nil
        }

        private func peek(_ offset: Int = 0) -> Character? {
            i + offset < chars.count ? chars[i + offset] : nil
        }
    }
}

/// the row shows "evaluatedExpression = display", so an expression still being typed is distinguishable
/// from a complete one by its prefix (e.g. "sin(42)*" shows "sin(42) = -0.917...")
struct LauncherCalculation {
    /// the complete part of the query that was evaluated (e.g. "sin(42)*" → "sin(42)", "sqrt(16" → "sqrt(16)")
    let evaluatedExpression: String
    /// shown in the results row: digit grouping and separators from the user's locale
    let display: String
    /// what gets copied on activation: machine-formatted, locale-independent; ISO 8601 for dates
    let raw: String
}
