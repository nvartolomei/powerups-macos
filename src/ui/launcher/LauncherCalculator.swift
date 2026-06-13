import Cocoa

/// evaluates the launcher query as an arithmetic expression: + - * /, power as ^ or **, parentheses,
/// unary minus, decimals, and basic functions like sqrt(2); ln is natural log, log is base 10
/// queries without an operator (plain numbers, app names) are not expressions, so they fall through to app search
/// expressions being typed evaluate their complete part: "sin(42)*", "sin(42)*sq", and "sin(42" all evaluate "sin(42)"
class LauncherCalculator {
    /// referenced from the background queue that scans apps, as cold icon loads hit the disk
    static let icon = NSWorkspace.shared.icon(forFile: NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.calculator")?.path ?? "/System/Applications/Calculator.app")
    private static let functions: [String: (Double) -> Double] = [
        "sqrt": sqrt, "cbrt": cbrt, "abs": abs, "exp": exp, "ln": log, "log": log10, "log2": log2,
        "sin": sin, "cos": cos, "tan": tan, "floor": floor, "ceil": ceil, "round": round,
    ]

    static func evaluate(_ query: String) -> LauncherCalculation? {
        let original = Array(query.filter { !$0.isWhitespace })
        guard original.contains(where: { "+-*/^()".contains($0) }) else { return nil }
        var chars = original
        while !chars.isEmpty {
            let completed = chars + [Character](repeating: ")", count: unclosedParens(chars))
            var parser = Parser(completed)
            if let value = parser.parseToEnd() {
                return LauncherCalculation(evaluatedExpression: formatExpression(completed), display: displayFormat(value), raw: rawFormat(value))
            }
            guard trimIncompleteTail(&chars) else { return nil }
        }
        return nil
    }

    private static func unclosedParens(_ chars: [Character]) -> Int {
        var depth = 0
        for c in chars {
            if c == "(" { depth += 1 }
            if c == ")" && depth > 0 { depth -= 1 }
        }
        return depth
    }

    /// an expression being typed ends with an operator, an open paren, or a partial function name
    /// dropping that tail evaluates the complete part, so the result doesn't flicker off mid-typing
    /// anything else (e.g. "1+password") is not an expression being typed, so it falls through to app search
    private static func trimIncompleteTail(_ chars: inout [Character]) -> Bool {
        guard let last = chars.last else { return false }
        if "+-*/^.(".contains(last) {
            chars.removeLast()
            return true
        }
        guard last.isLetter || last.isNumber else { return false }
        var start = chars.count
        while start > 0 && (chars[start - 1].isLetter || chars[start - 1].isNumber) { start -= 1 }
        while start < chars.count && chars[start].isNumber { start += 1 }
        guard start < chars.count, functions.keys.contains(where: { $0.hasPrefix(String(chars[start...])) }) else { return false }
        chars.removeSubrange(start...)
        return true
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

    /// recursive descent over precedence levels: addition := multiplication (('+'|'-') multiplication)*, etc.
    /// unary minus binds looser than power so that "-2^2" is -4; power is right-associative
    /// every intermediate value must be finite: IEEE would quietly give "1/(1/(1-1))" = 1/inf = 0
    private struct Parser {
        private let chars: [Character]
        private var i = 0

        init(_ chars: [Character]) {
            self.chars = chars
        }

        mutating func parseToEnd() -> Double? {
            guard let value = addition(), i == chars.count else { return nil }
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
            while let op = peek(), op == "*" || op == "/" {
                i += 1
                guard let rhs = unary(), let next = finite(op == "*" ? value * rhs : value / rhs) else { return nil }
                value = next
            }
            return value
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

        private mutating func primary() -> Double? {
            if peek() == "(" { return parenthesized() }
            if let c = peek(), c.isLetter { return functionCall() }
            return number()
        }

        private mutating func parenthesized() -> Double? {
            i += 1
            guard let value = addition(), peek() == ")" else { return nil }
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
    /// what gets copied on activation: machine-formatted, locale-independent
    let raw: String
}
