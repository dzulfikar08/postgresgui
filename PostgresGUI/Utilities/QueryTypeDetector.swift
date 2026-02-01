//
//  QueryTypeDetector.swift
//  PostgresGUI
//
//  Created by Claude on 12/25/25.
//

import Foundation

enum QueryType: Equatable {
    case select
    case insert
    case update
    case delete
    case createTable
    case dropTable
    case alterTable
    case other

    nonisolated static func == (lhs: QueryType, rhs: QueryType) -> Bool {
        switch (lhs, rhs) {
        case (.select, .select),
             (.insert, .insert),
             (.update, .update),
             (.delete, .delete),
             (.createTable, .createTable),
             (.dropTable, .dropTable),
             (.alterTable, .alterTable),
             (.other, .other):
            return true
        default:
            return false
        }
    }

    var isMutation: Bool {
        switch self {
        case .select, .other:
            return false
        case .insert, .update, .delete, .createTable, .dropTable, .alterTable:
            return true
        }
    }

    var successTitle: String {
        switch self {
        case .select:
            return "Query Executed"
        case .insert:
            return "Insert Successful"
        case .update:
            return "Update Successful"
        case .delete:
            return "Delete Successful"
        case .createTable:
            return "Table Created"
        case .dropTable:
            return "Table Dropped"
        case .alterTable:
            return "Table Altered"
        case .other:
            return "Query Executed"
        }
    }
}

struct QueryTypeDetector {

    static func detect(_ sql: String) -> QueryType {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        if trimmed.hasPrefix("SELECT") || trimmed.hasPrefix("WITH") {
            return .select
        }
        if trimmed.hasPrefix("INSERT") {
            return .insert
        }
        if trimmed.hasPrefix("UPDATE") {
            return .update
        }
        if trimmed.hasPrefix("DELETE") {
            return .delete
        }
        if trimmed.range(of: "^CREATE\\s+(TEMP(ORARY)?\\s+)?TABLE", options: .regularExpression) != nil {
            return .createTable
        }
        if trimmed.range(of: "^DROP\\s+TABLE", options: .regularExpression) != nil {
            return .dropTable
        }
        if trimmed.range(of: "^ALTER\\s+TABLE", options: .regularExpression) != nil {
            return .alterTable
        }

        return .other
    }

    static func extractTableName(_ sql: String) -> String? {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)

        // Pattern for table names: either "quoted identifier" or unquoted_identifier
        // Quoted can contain spaces, unquoted cannot
        let tableNamePattern = "(?:\"[^\"]+\"|[\\w\\.]+)"

        // SELECT ... FROM table_name
        if let match = trimmed.range(of: "\\bFROM\\s+(\(tableNamePattern))", options: [.regularExpression, .caseInsensitive]) {
            let matched = String(trimmed[match])
            if let tableMatch = matched.range(of: "FROM\\s+(\(tableNamePattern))", options: [.regularExpression, .caseInsensitive]) {
                var tablePart = String(matched[tableMatch]).replacingOccurrences(of: "FROM", with: "", options: .caseInsensitive)
                tablePart = tablePart.trimmingCharacters(in: .whitespaces)
                return cleanTableName(tablePart)
            }
        }

        // INSERT INTO table_name
        if let match = trimmed.range(of: "INSERT\\s+INTO\\s+(\(tableNamePattern))", options: [.regularExpression, .caseInsensitive]) {
            let afterInsertInto = trimmed[match]
            if let tableMatch = afterInsertInto.range(of: "INTO\\s+(\(tableNamePattern))", options: [.regularExpression, .caseInsensitive]) {
                var tablePart = String(afterInsertInto[tableMatch]).replacingOccurrences(of: "INTO", with: "", options: .caseInsensitive)
                tablePart = tablePart.trimmingCharacters(in: .whitespaces)
                return cleanTableName(tablePart)
            }
        }

        // UPDATE table_name SET
        if let match = trimmed.range(of: "UPDATE\\s+(\(tableNamePattern))", options: [.regularExpression, .caseInsensitive]) {
            var tablePart = String(trimmed[match]).replacingOccurrences(of: "UPDATE", with: "", options: .caseInsensitive)
            tablePart = tablePart.trimmingCharacters(in: .whitespaces)
            return cleanTableName(tablePart)
        }

        // DELETE FROM table_name
        if let match = trimmed.range(of: "DELETE\\s+FROM\\s+(\(tableNamePattern))", options: [.regularExpression, .caseInsensitive]) {
            let afterDeleteFrom = trimmed[match]
            if let tableMatch = afterDeleteFrom.range(of: "FROM\\s+(\(tableNamePattern))", options: [.regularExpression, .caseInsensitive]) {
                var tablePart = String(afterDeleteFrom[tableMatch]).replacingOccurrences(of: "FROM", with: "", options: .caseInsensitive)
                tablePart = tablePart.trimmingCharacters(in: .whitespaces)
                return cleanTableName(tablePart)
            }
        }

        // CREATE TABLE table_name
        if let match = trimmed.range(of: "CREATE\\s+(TEMP(ORARY)?\\s+)?TABLE\\s+(IF\\s+NOT\\s+EXISTS\\s+)?(\(tableNamePattern))", options: [.regularExpression, .caseInsensitive]) {
            let matched = String(trimmed[match])
            // For quoted names, extract the quoted part; for unquoted, get last token
            if let quotedMatch = matched.range(of: "\"[^\"]+\"", options: .regularExpression) {
                return cleanTableName(String(matched[quotedMatch]))
            }
            let components = matched.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if let last = components.last {
                return cleanTableName(last)
            }
        }

        // DROP TABLE table_name
        if let match = trimmed.range(of: "DROP\\s+TABLE\\s+(IF\\s+EXISTS\\s+)?(\(tableNamePattern))", options: [.regularExpression, .caseInsensitive]) {
            let matched = String(trimmed[match])
            if let quotedMatch = matched.range(of: "\"[^\"]+\"", options: .regularExpression) {
                return cleanTableName(String(matched[quotedMatch]))
            }
            let components = matched.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if let last = components.last {
                return cleanTableName(last)
            }
        }

        // ALTER TABLE table_name
        if let match = trimmed.range(of: "ALTER\\s+TABLE\\s+(\(tableNamePattern))", options: [.regularExpression, .caseInsensitive]) {
            let matched = String(trimmed[match])
            if let quotedMatch = matched.range(of: "\"[^\"]+\"", options: .regularExpression) {
                return cleanTableName(String(matched[quotedMatch]))
            }
            let components = matched.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if let last = components.last {
                return cleanTableName(last)
            }
        }

        return nil
    }

    private static func cleanTableName(_ name: String) -> String {
        var cleaned = name
        // Remove quotes
        cleaned = cleaned.replacingOccurrences(of: "\"", with: "")
        cleaned = cleaned.replacingOccurrences(of: "'", with: "")
        // Handle schema.table - extract just table name
        if cleaned.contains(".") {
            cleaned = cleaned.components(separatedBy: ".").last ?? cleaned
        }
        return cleaned
    }
}
