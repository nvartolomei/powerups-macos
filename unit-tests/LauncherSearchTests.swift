import XCTest

final class LauncherSearchTests: XCTestCase {
    private func rank(_ query: String, _ name: String) -> Int? {
        LauncherSearch.matchRank(LauncherSearch.normalizedQuery(query), LauncherSearch.humpWords(name), name.lowercased())
    }

    func testHumpsOnSpaces() throws {
        XCTAssertEqual(rank("vsc", "Visual Studio Code"), 0)
        XCTAssertEqual(rank("vsco", "Visual Studio Code"), 0)
        XCTAssertEqual(rank("vscode", "Visual Studio Code"), 0)
        XCTAssertEqual(rank("visual studio", "Visual Studio Code"), 0)
    }

    func testHumpsOnUppercase() throws {
        XCTAssertEqual(rank("vsco", "VisualStudioCode"), 0)
    }

    func testHumpsCanSkipWords() throws {
        XCTAssertEqual(rank("vc", "Visual Studio Code"), 0)
    }

    func testHumpsFromLaterWordRankLower() throws {
        XCTAssertEqual(rank("chr", "My Chrome"), 1)
        XCTAssertEqual(rank("code", "Visual Studio Code"), 1)
    }

    func testSubstringRanksLast() throws {
        XCTAssertEqual(rank("code", "Xcode"), 2)
        XCTAssertEqual(rank("shop", "Photoshop"), 2)
    }

    func testCommandNamesMatchShortQueries() throws {
        XCTAssertEqual(rank("ls", "Output: LSX"), 1)
        XCTAssertEqual(rank("lsx", "Output: LSX"), 1)
        XCTAssertEqual(rank("dar", "Switch to Dark Mode"), 1)
        XCTAssertEqual(rank("out", "Output: LSX"), 0)
    }

    /// a deep path whose segments share a prefix reaches the same (query position, word) pair through many branches;
    /// unmemoized this took ~50s, so a 1s bound can't flake
    func testSimilarWordsDoNotBacktrackExponentially() throws {
        let name = "VSCode: ~/" + Array(repeating: "aab", count: 22).joined(separator: "/")
        let startTime = DispatchTime.now().uptimeNanoseconds
        XCTAssertNil(rank("aaaaaaaaaaaaaaaaaaz", name))
        XCTAssertLessThan(Double(DispatchTime.now().uptimeNanoseconds - startTime) / 1_000_000_000, 1)
    }

    func testNoMatch() throws {
        XCTAssertNil(rank("vsco", "Discord"))
        XCTAssertNil(rank("vscode", "Xcode"))
        XCTAssertNil(rank("xyz", "Visual Studio Code"))
    }
}
