import XCTest

final class LauncherCalculatorTests: XCTestCase {
    private func raw(_ query: String) -> String? {
        LauncherCalculator.evaluate(query)?.raw
    }

    func testBasicOperations() throws {
        XCTAssertEqual(raw("2+2"), "4")
        XCTAssertEqual(raw("7-10"), "-3")
        XCTAssertEqual(raw("6*7"), "42")
        XCTAssertEqual(raw("1/4"), "0.25")
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
}
