//
//  SQLCompletionServiceProtocol.swift
//  PostgresGUI
//
//  Protocol for SQL completion service
//

import Foundation

@MainActor
protocol SQLCompletionServiceProtocol {
    /// Get completion suggestions for a partial word
    /// - Parameters:
    ///   - partialWord: The text the user has typed so far
    ///   - context: The SQL context at the cursor position
    /// - Returns: Array of completion suggestions
    func getCompletions(for partialWord: String, inContext context: SQLContext) -> [CompletionSuggestion]

    /// Detect the SQL context at a cursor position
    /// - Parameters:
    ///   - range: The cursor range
    ///   - text: The full text to analyze
    /// - Returns: The detected SQL context
    func detectContext(at range: NSRange, inText text: String) -> SQLContext
}
