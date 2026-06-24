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

    func testNoMatch() throws {
        XCTAssertNil(rank("vsco", "Discord"))
        XCTAssertNil(rank("vscode", "Xcode"))
        XCTAssertNil(rank("xyz", "Visual Studio Code"))
    }
}
