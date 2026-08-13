import XCTest

final class LauncherCalculatorTests: XCTestCase {
    private func raw(_ query: String) -> String? {
        LauncherCalculator.evaluate(query)?.raw
    }

    private func expression(_ query: String) -> String? {
        LauncherCalculator.evaluate(query)?.evaluatedExpression
    }

    func testBasicOperations() throws {
        XCTAssertEqual(raw("2+2"), "4")
        XCTAssertEqual(raw("7-10"), "-3")
        XCTAssertEqual(raw("6*7"), "42")
        XCTAssertEqual(raw("1/4"), "0.25")
    }

    func testModulo() throws {
        XCTAssertEqual(raw("10%3"), "1")
        XCTAssertEqual(raw("10%4"), "2")
        XCTAssertEqual(raw("5.5%2"), "1.5")
        XCTAssertEqual(raw("-7%3"), "-1")
        XCTAssertEqual(raw("2+10%3"), "3")
        XCTAssertEqual(raw("10%3*2"), "2")
        XCTAssertEqual(raw("2^10%3"), "1")
        XCTAssertEqual(raw("10%"), "10")
        XCTAssertNil(raw("10%0"))
        XCTAssertEqual(LauncherCalculator.evaluate("10%3")?.evaluatedExpression, "10 % 3")
    }

    func testPrecedenceAndParentheses() throws {
        XCTAssertEqual(raw("2+3*4"), "14")
        XCTAssertEqual(raw("(2+3)*4"), "20")
        XCTAssertEqual(raw("2*(3+4)/2"), "7")
    }

    func testExponentiation() throws {
        XCTAssertEqual(raw("2^10"), "1024")
        XCTAssertEqual(raw("2**10"), "1024")
        XCTAssertEqual(raw("2^3^2"), "512")
        XCTAssertEqual(raw("2**3**2"), "512")
        XCTAssertEqual(raw("-2^2"), "-4")
        XCTAssertEqual(raw("2^-1"), "0.5")
        XCTAssertEqual(raw("2*3"), "6")
    }

    func testBitshift() throws {
        XCTAssertEqual(raw("4<<30"), "4294967296")
        XCTAssertEqual(raw("1<<0"), "1")
        XCTAssertEqual(raw("1<<2+3"), "32")
        XCTAssertEqual(raw("1<<2<<3"), "32")
        XCTAssertEqual(raw("2^2<<1"), "8")
        XCTAssertEqual(raw("(1<<10)/2"), "512")
        XCTAssertEqual(raw("sqrt(1<<4)"), "4")
        XCTAssertEqual(raw("-2<<2"), "-8")
        XCTAssertEqual(raw("1<<40"), "1099511627776")
        XCTAssertEqual(raw("1<<64"), "1.844674407e+19")
        XCTAssertEqual(raw("4<<"), "4")
        XCTAssertNil(raw("1.5<<1"))
        XCTAssertNil(raw("1<<0.5"))
        XCTAssertNil(raw("1<<-1"))
        XCTAssertNil(raw("1<<9999"))
        XCTAssertNil(raw("4<5"))
        XCTAssertEqual(LauncherCalculator.evaluate("4<<30")?.evaluatedExpression, "4 << 30")
    }

    func testUnaryMinus() throws {
        XCTAssertEqual(raw("-5+10"), "5")
        XCTAssertEqual(raw("2*-3"), "-6")
        XCTAssertEqual(raw("0*-1"), "0")
    }

    func testDecimalsAndSpaces() throws {
        XCTAssertEqual(raw("1.5 + 2.25"), "3.75")
        XCTAssertEqual(raw(".5+.5"), "1")
        XCTAssertEqual(raw("0.1+0.2"), "0.3")
        XCTAssertEqual(raw("1/3"), "0.3333333333")
        XCTAssertEqual(raw("2^40"), "1099511627776")
    }

    func testFunctions() throws {
        XCTAssertEqual(raw("sqrt(16)"), "4")
        XCTAssertEqual(raw("sqrt(2+2)"), "2")
        XCTAssertEqual(raw("sqrt(sqrt(16))"), "2")
        XCTAssertEqual(raw("2*sqrt(9)+1"), "7")
        XCTAssertEqual(raw("abs(-5)"), "5")
        XCTAssertEqual(raw("ln(1)"), "0")
        XCTAssertEqual(raw("log(1000)"), "3")
        XCTAssertEqual(raw("log2(8)"), "3")
        XCTAssertEqual(raw("cos(0)"), "1")
        XCTAssertEqual(raw("floor(1.7)"), "1")
        XCTAssertNil(raw("foo(2)"))
        XCTAssertNil(raw("sqrt(-1)"))
    }

    func testIncompleteExpressionsEvaluateTheCompletePart() throws {
        XCTAssertEqual(raw("2+"), "2")
        XCTAssertEqual(raw("2+3*"), "5")
        XCTAssertEqual(raw("2**"), "2")
        XCTAssertEqual(raw("sin(42)*"), raw("sin(42)"))
        XCTAssertEqual(raw("sqrt(16"), "4")
        XCTAssertEqual(raw("(2+3"), "5")
        XCTAssertEqual(raw("sqrt(16)+sq"), "4")
        XCTAssertEqual(raw("8*log2"), "8")
        XCTAssertNil(raw("1+password"))
        XCTAssertNil(raw("sin("))
    }

    func testEvaluatedExpressionIsTheCompletePart() throws {
        XCTAssertEqual(LauncherCalculator.evaluate("2+2")?.evaluatedExpression, "2 + 2")
        XCTAssertEqual(LauncherCalculator.evaluate("2 + 2")?.evaluatedExpression, "2 + 2")
        XCTAssertEqual(LauncherCalculator.evaluate("sin(42)*")?.evaluatedExpression, "sin(42)")
        XCTAssertEqual(LauncherCalculator.evaluate("sqrt(16")?.evaluatedExpression, "sqrt(16)")
        XCTAssertEqual(LauncherCalculator.evaluate("2+3*")?.evaluatedExpression, "2 + 3")
        XCTAssertEqual(LauncherCalculator.evaluate("sqrt(16)+sq")?.evaluatedExpression, "sqrt(16)")
    }

    func testEvaluatedExpressionSpacesOperators() throws {
        XCTAssertEqual(LauncherCalculator.evaluate("((42*5)/8+26-sqrt(42*2))")?.evaluatedExpression, "((42 * 5) / 8 + 26 - sqrt(42 * 2))")
        XCTAssertEqual(LauncherCalculator.evaluate("-2^2")?.evaluatedExpression, "-2 ^ 2")
        XCTAssertEqual(LauncherCalculator.evaluate("2*-3")?.evaluatedExpression, "2 * -3")
        XCTAssertEqual(LauncherCalculator.evaluate("2**10")?.evaluatedExpression, "2 ** 10")
    }

    func testDisplayIsLocalized() throws {
        let enUS = Locale(identifier: "en_US")
        XCTAssertEqual(LauncherCalculator.displayFormat(1099511627776, enUS), "1,099,511,627,776")
        XCTAssertEqual(LauncherCalculator.displayFormat(0.25, enUS), "0.25")
        XCTAssertEqual(LauncherCalculator.displayFormat(1.0 / 3.0, enUS), "0.3333333333")
        XCTAssertEqual(LauncherCalculator.displayFormat(0.1 + 0.2, enUS), "0.3")
        let deDE = Locale(identifier: "de_DE")
        XCTAssertEqual(LauncherCalculator.displayFormat(1234.5, deDE), "1.234,5")
    }

    func testPlainNumbersAreNotExpressions() throws {
        XCTAssertNil(raw("5"))
        XCTAssertNil(raw("3.14"))
        XCTAssertNil(raw("1password"))
    }

    func testInvalidExpressions() throws {
        XCTAssertNil(raw(""))
        XCTAssertNil(raw("2(3)"))
        XCTAssertNil(raw("5..5+1"))
        XCTAssertNil(raw("visual-studio"))
        XCTAssertNil(raw("c++"))
    }

    func testNonFiniteResults() throws {
        XCTAssertNil(raw("1/0"))
        XCTAssertNil(raw("0/0"))
        XCTAssertNil(raw("9^9999"))
        XCTAssertNil(raw("1/0*"))
    }

    /// IEEE would quietly give 1/inf = 0; non-finite intermediates must fail instead
    func testNonFiniteIntermediates() throws {
        XCTAssertNil(raw("1/(1/(1-1))"))
        XCTAssertNil(raw("1/(1/0)"))
        XCTAssertNil(raw("0*(1/0)"))
        XCTAssertNil(raw("9^9999/9^9999"))
    }

    func testUnitSuffixesMultiplyIntoBaseUnits() throws {
        XCTAssertEqual(raw("5GiB"), "5368709120")
        XCTAssertEqual(raw("2KB"), "2000")
        XCTAssertEqual(raw("90min"), "5400")
        XCTAssertEqual(raw("1GiB/4KiB"), "262144")
        XCTAssertEqual(raw("(1+2)GiB in MB"), "3221.225472")
        XCTAssertEqual(raw("-5d"), "-432000")
        XCTAssertNil(raw("5Gi"))
        XCTAssertNil(raw("5M"))
        XCTAssertNil(raw("5x+1"))
    }

    func testDataSizeConversions() throws {
        XCTAssertEqual(raw("3<<30 in MiB"), "3072")
        XCTAssertEqual(raw("3<<30 to MiB"), "3072")
        XCTAssertEqual(raw("3<<30 in GB"), "3.221225472")
        XCTAssertEqual(raw("5GiB in MB"), "5368.70912")
        XCTAssertEqual(raw("5GiB + 300MiB in GB"), "5.68328192")
        XCTAssertEqual(raw("4096 in KiB"), "4")
        XCTAssertEqual(raw("1<<10 in KiB"), "1")
        XCTAssertEqual(raw("5gib in mb"), "5368.70912")
        XCTAssertEqual(raw("10GiB / 125MB in s"), "85.89934592")
        XCTAssertEqual(raw("1gbit in MB"), "125")
    }

    func testTimeConversions() throws {
        XCTAssertEqual(raw("90min in h"), "1.5")
        XCTAssertEqual(raw("3d in h"), "72")
        XCTAssertEqual(raw("1.5h + 20min in s"), "6600")
        XCTAssertEqual(raw("250ms in s"), "0.25")
        XCTAssertEqual(raw("3600 in h"), "1")
        XCTAssertEqual(raw("1w in d"), "7")
        XCTAssertEqual(raw("500us in ms"), "0.5")
        XCTAssertEqual(raw("2hr in min"), "120")
        XCTAssertEqual(raw("1786613400123ms in s"), "1786613400.123")
    }

    func testTimestampConversions() throws {
        XCTAssertEqual(raw("1786613400 in date"), "2026-08-13T09:30:00Z")
        XCTAssertEqual(raw("1786613400 in utc"), "2026-08-13T09:30:00Z")
        XCTAssertEqual(raw("1786613400123 in utc"), "2026-08-13T09:30:00.123Z")
        XCTAssertEqual(raw("1786613400123ms in utc"), "2026-08-13T09:30:00.123Z")
        XCTAssertEqual(raw("1786613400 + 3d in utc"), "2026-08-16T09:30:00Z")
        XCTAssertEqual(raw("-1786613400 in utc"), "1913-05-21T14:30:00Z")
        XCTAssertEqual(expression("1786613400 in utc"), "1786613400 in utc")
        XCTAssertNil(raw("99^99 in date"))
    }

    func testPassiveTimestampDetection() throws {
        XCTAssertEqual(LauncherCalculator.timestamp("1786613400")?.raw, "2026-08-13T09:30:00Z")
        XCTAssertEqual(LauncherCalculator.timestamp("1786613400")?.evaluatedExpression, "1786613400")
        XCTAssertEqual(LauncherCalculator.timestamp("1786613400123")?.raw, "2026-08-13T09:30:00.123Z")
        XCTAssertEqual(LauncherCalculator.timestamp(" 1786613400 ")?.raw, "2026-08-13T09:30:00Z")
        XCTAssertNil(LauncherCalculator.timestamp("6175551234"))
        XCTAssertNil(LauncherCalculator.timestamp("978307199"))
        XCTAssertNil(LauncherCalculator.timestamp("12345678901"))
        XCTAssertNil(LauncherCalculator.timestamp("1786613400.5"))
        XCTAssertNil(LauncherCalculator.timestamp("2+2"))
    }

    func testConversionsBeingTypedEvaluateTheCompletePart() throws {
        XCTAssertEqual(raw("3<<30 i"), "3221225472")
        XCTAssertEqual(raw("3<<30 in"), "3221225472")
        XCTAssertEqual(raw("3<<30 in M"), "3221225472")
        XCTAssertEqual(expression("3<<30 in Mi"), "3 << 30")
        XCTAssertEqual(raw("5GiB in"), "5368709120")
        XCTAssertEqual(raw("3<<30+ in MiB"), "3072")
        XCTAssertEqual(expression("5m in KB"), "5 in KB")
        XCTAssertNil(raw("5 in xyz"))
        XCTAssertNil(raw("5 in s in ms"))
        XCTAssertNil(raw("1 to 2"))
        XCTAssertNil(raw("x in h + 5"))
        XCTAssertNil(raw("in mb"))
    }

    func testEvaluatedExpressionNormalizesUnits() throws {
        XCTAssertEqual(expression("3<<30 in mib"), "3 << 30 in MiB")
        XCTAssertEqual(expression("5gib in mb"), "5 GiB in MB")
        XCTAssertEqual(expression("90min in h"), "90 min in h")
        XCTAssertEqual(expression("5GiB TO MB"), "5 GiB to MB")
        XCTAssertEqual(expression("1GiB/4KiB"), "1 GiB / 4 KiB")
        XCTAssertEqual(expression("2hr in min"), "2 h in min")
    }

    func testConvertedDisplayShowsUnit() throws {
        let enUS = Locale(identifier: "en_US")
        XCTAssertEqual(LauncherCalculator.convertedDisplay(3072, "MiB", enUS), "3,072 MiB")
        XCTAssertEqual(LauncherCalculator.convertedDisplay(5368.70912, "MB", enUS), "5,368.70912 MB")
        XCTAssertEqual(LauncherCalculator.convertedDisplay(1786613400.123, "s", enUS), "1,786,613,400.123 s")
    }

    func testDateDisplayIsLabeled() throws {
        let enUS = Locale(identifier: "en_US")
        let utc = TimeZone(identifier: "UTC")!
        let plusTwo = TimeZone(secondsFromGMT: 7200)!
        // en_US renders a narrow no-break space before AM/PM
        XCTAssertEqual(LauncherCalculator.dateDisplay(1786613400, utc, enUS), "Aug 13, 2026 at 9:30:00\u{202F}AM UTC")
        XCTAssertEqual(LauncherCalculator.dateDisplay(1786613400.123, utc, enUS), "Aug 13, 2026 at 9:30:00.123\u{202F}AM UTC")
        XCTAssertEqual(LauncherCalculator.dateDisplay(1786613400, plusTwo, enUS), "Aug 13, 2026 at 11:30:00\u{202F}AM GMT+2")
        XCTAssertEqual(LauncherCalculator.dateRaw(1786613400, plusTwo), "2026-08-13T11:30:00+02:00")
    }
}
