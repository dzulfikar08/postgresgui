//
//  SQLCompletionService.swift
//  PostgresGUI
//
//  Service for SQL auto-completion
//

import Foundation
import Logging

@MainActor
class SQLCompletionService: SQLCompletionServiceProtocol {
    private let cache: CompletionCacheProtocol
    private let tokenizer: SQLTokenizer
    private let logger = Logger.debugLogger(label: "com.postgresgui.sqlcompletionservice")

    /// SQL keywords for default completion
    private let sqlKeywords: [String] = [
        "SELECT", "FROM", "WHERE", "JOIN", "INNER", "LEFT", "RIGHT", "OUTER",
        "INSERT", "UPDATE", "DELETE", "CREATE", "DROP", "ALTER",
        "AND", "OR", "NOT", "IN", "LIKE", "IS", "NULL", "ORDER", "BY", "GROUP", "HAVING"
    ]

    init(cache: CompletionCacheProtocol, tokenizer: SQLTokenizer) {
        self.cache = cache
        self.tokenizer = tokenizer
    }

    /// Get completion suggestions for a partial word
    func getCompletions(for partialWord: String, inContext context: SQLContext) -> [CompletionSuggestion] {
        guard !partialWord.isEmpty else { return [] }

        var suggestions: [CompletionSuggestion] = []

        switch context {
        case .fromClause:
            // Suggest table names
            if let tables = cache.getTables(forDatabase: getCurrentDatabaseId()) {
                suggestions = appendMatches(for: partialWord, from: tables, kind: .table)
            }

        case .selectClause, .whereClause:
            // Suggest column names
            suggestions = getColumnsStarting(with: partialWord)

        case .tableReference:
            // Suggest columns from referenced table
            // TODO: Parse table reference and get its columns
            break

        case .defaultContext:
            // Suggest keywords and table names
            suggestions = getKeywordsStarting(with: partialWord)
            if let tables = cache.getTables(forDatabase: getCurrentDatabaseId()) {
                suggestions.append(contentsOf: appendMatches(for: partialWord, from: tables, kind: .table))
            }
        }

        // Sort by relevance score
        return suggestions.sorted { $0.relevanceScore > $1.relevanceScore }
    }

    /// Detect the SQL context at a cursor position
    func detectContext(at range: NSRange, inText text: String) -> SQLContext {
        return tokenizer.getContext(at: range, inText: text)
    }

    // MARK: - Private Helpers

    private func getColumnsStarting(with prefix: String) -> [CompletionSuggestion] {
        // TODO: Get columns from all tables in current query context
        return []

        // Placeholder implementation:
        // if let tables = getTablesInCurrentQuery() {
        //     for table in tables {
        //         if let columns = cache.getColumns(forTable: table.name, inSchema: table.schema) {
        //             suggestions.append(contentsOf: appendMatches(for: prefix, from: columns, kind: .column))
        //         }
        //     }
        // }
    }

    private func getKeywordsStarting(with prefix: String) -> [CompletionSuggestion] {
        let upperPrefix = prefix.uppercased()
        return sqlKeywords
            .filter { $0.hasPrefix(upperPrefix) }
            .map { keyword in
                CompletionSuggestion(
                    text: keyword,
                    displayText: "\(keyword) (keyword)",
                    kind: .keyword,
                    relevanceScore: 80
                )
            }
    }

    private func appendMatches<T>(for prefix: String, from items: [T], kind: CompletionSuggestion.CompletionKind) -> [CompletionSuggestion] where T: NameProvider {
        let lowerPrefix = prefix.lowercased()
        return items.compactMap { item -> CompletionSuggestion? in
            let name = item.getName()
            let lowerName = name.lowercased()

            // Calculate fuzzy match score
            let score = fuzzyMatchScore(query: lowerPrefix, target: lowerName)

            if score >= 40 { // Minimum threshold
                return CompletionSuggestion(
                    text: name,
                    displayText: "\(name) (\(kind.rawValue))",
                    kind: kind,
                    relevanceScore: score
                )
            }
            return nil
        }
    }

    /// Calculate fuzzy match score (0-100)
    private func fuzzyMatchScore(query: String, target: String) -> Int {
        if query.isEmpty { return 0 }

        // Exact match
        if target == query {
            return 100
        }

        // Prefix match
        if target.hasPrefix(query) {
            return 80
        }

        // Skip match (characters in order, allowing gaps)
        if isSkipMatch(query: query, target: target) {
            return 60
        }

        // Fuzzy match (allows 1 typo)
        if isFuzzyMatch(query: query, target: target) {
            return 40
        }

        return 0
    }

    private func isSkipMatch(query: String, target: String) -> Bool {
        var queryIndex = query.startIndex
        var targetIndex = target.startIndex

        while queryIndex < query.endIndex && targetIndex < target.endIndex {
            if query[queryIndex] == target[targetIndex] {
                queryIndex = query.index(after: queryIndex)
            }
            targetIndex = target.index(after: targetIndex)
        }

        return queryIndex == query.endIndex
    }

    private func isFuzzyMatch(query: String, target: String) -> Bool {
        // Simple fuzzy matching allowing 1 character difference
        let queryCount = query.count
        let targetCount = target.count

        if abs(queryCount - targetCount) <= 1 {
            let distance = levenshteinDistance(query, target)
            return distance <= 1
        }

        return false
    }

    private func levenshteinDistance(_ a: String, _ b: String) -> Int {
        let aCount = a.count
        let bCount = b.count

        var matrix = Array(repeating: Array(repeating: 0, count: bCount + 1), count: aCount + 1)

        for i in 0...aCount {
            matrix[i][0] = i
        }

        for j in 0...bCount {
            matrix[0][j] = j
        }

        for i in 1...aCount {
            for j in 1...bCount {
                let cost = a[a.index(a.startIndex, offsetBy: i - 1)] == b[b.index(b.startIndex, offsetBy: j - 1)] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,      // deletion
                    matrix[i][j - 1] + 1,      // insertion
                    matrix[i - 1][j - 1] + cost // substitution
                )
            }
        }

        return matrix[aCount][bCount]
    }

    private func getCurrentDatabaseId() -> String {
        // TODO: Get from AppState
        return "default"
    }
}

/// Protocol for items that have names
protocol NameProvider {
    func getName() -> String
}

extension TableInfo: NameProvider {
    func getName() -> String { return name }
}

extension ColumnInfo: NameProvider {
    func getName() -> String { return name }
}
