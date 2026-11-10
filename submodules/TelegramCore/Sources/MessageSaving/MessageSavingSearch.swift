import Foundation

/// Matches words and filename prefixes with the same case-insensitive semantics
/// as local chat search. Cloud messages are not in Postbox's secret-chat text index.
///
/// The kept messages live in our own store, not in Postbox, so there is no local-tag
/// query to run here — the saved records are filtered directly.
public func ayuGramSavedMessageMatchesQuery(text: String, query: String) -> Bool {
    func words(_ value: String) -> [String] {
        return value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
    let queryWords = words(query)
    let textWords = words(text)
    return queryWords.allSatisfy { queryWord in
        textWords.contains { $0.hasPrefix(queryWord) }
    }
}
