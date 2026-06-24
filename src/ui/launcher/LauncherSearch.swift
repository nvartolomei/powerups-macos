import Foundation

/// anything the launcher ranks: `words`/`lowercasedName` feed `matchRank`, `name` breaks ties between equal ranks
protocol LauncherSearchable {
    var name: String { get }
    var lowercasedName: String { get }
    var words: [[Character]] { get }
}

/// hump search: app names are split into words (on spaces/punctuation, and on camelCase humps)
/// a query matches if it can be consumed, in order, as prefixes of a subsequence of those words
/// e.g. "vsc", "vsco", and "vscode" all match "Visual Studio Code" and "VisualStudioCode"
class LauncherSearch {
    /// lower ranks are better matches: 0 = humps from the first word, 1 = humps from a later word, 2 = plain substring
    static func matchRank(_ query: [Character], _ words: [[Character]], _ lowercasedName: String) -> Int? {
        for firstWord in 0..<words.count {
            if matchesWordPrefixes(query, 0, words, firstWord) {
                return firstWord == 0 ? 0 : 1
            }
        }
        if lowercasedName.contains(String(query)) { return 2 }
        return nil
    }

    static func normalizedQuery(_ query: String) -> [Character] {
        Array(query.lowercased()).filter { $0.isLetter || $0.isNumber }
    }

    static func humpWords(_ name: String) -> [[Character]] {
        let chars = Array(name)
        var words = [[Character]]()
        var current = [Character]()
        for i in 0..<chars.count {
            let c = chars[i]
            if !c.isLetter && !c.isNumber {
                if !current.isEmpty { words.append(current); current = [] }
            } else {
                if !current.isEmpty && chars[i - 1].isLowercase && c.isUppercase {
                    words.append(current)
                    current = []
                }
                current.append(contentsOf: String(c).lowercased())
            }
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    /// query[qi...] consumed as prefixes of words, the next prefix taken from words[wi]
    private static func matchesWordPrefixes(_ query: [Character], _ qi: Int, _ words: [[Character]], _ wi: Int) -> Bool {
        let word = words[wi]
        var len = 0
        while len < word.count && qi + len < query.count && word[len] == query[qi + len] {
            len += 1
            if qi + len == query.count { return true }
            for next in (wi + 1)..<words.count {
                if matchesWordPrefixes(query, qi + len, words, next) { return true }
            }
        }
        return false
    }
}
