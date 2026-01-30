//
//  QueryWrapping.swift
//  PostgresGUI
//
//  Provides reusable query wrapping helpers for display-safe results.
//

import Foundation

enum QueryWrapPolicy {
    case none
    case wrapSelectResults
}

struct WrappedQuery {
    let sql: String
    let isWrapped: Bool
    let expectedColumnNames: [String]?
}

struct QueryWrapper {
    static func wrapIfNeeded(sql: String, policy: QueryWrapPolicy) -> WrappedQuery {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = stripTrailingSemicolons(trimmed)

        guard policy == .wrapSelectResults else {
            return WrappedQuery(sql: stripped, isWrapped: false, expectedColumnNames: nil)
        }

        let queryType = QueryTypeDetector.detect(stripped)
        guard queryType == .select else {
            return WrappedQuery(sql: stripped, isWrapped: false, expectedColumnNames: nil)
        }

        let wrappedSQL = """
        SELECT to_jsonb(q) AS row
        FROM (
        \(stripped)
        ) q
        """

        return WrappedQuery(sql: wrappedSQL, isWrapped: true, expectedColumnNames: ["row"])
    }

    private static func stripTrailingSemicolons(_ sql: String) -> String {
        var result = sql
        while result.last == ";" {
            result.removeLast()
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }
}
