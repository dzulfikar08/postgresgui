//
//  CompletionSuggestionTests.swift
//  PostgresGUITests
//
//  Unit tests for CompletionSuggestion model
//

import Testing
@testable import PostgresGUI

@Suite("CompletionSuggestion Tests")
struct CompletionSuggestionTests {
    @Test("Suggestion initializes correctly")
    func suggestionInitialization() {
        let suggestion = CompletionSuggestion(
            text: "username",
            displayText: "username (text)",
            kind: .column,
            relevanceScore: 100
        )

        #expect(suggestion.text == "username")
        #expect(suggestion.displayText == "username (text)")
        #expect(suggestion.kind == .column)
        #expect(suggestion.relevanceScore == 100)
    }

    @Test("Suggestion conforms to Identifiable")
    func suggestionConformsToIdentifiable() {
        let suggestion = CompletionSuggestion(
            text: "test",
            displayText: "test",
            kind: .keyword,
            relevanceScore: 50
        )
        #expect(suggestion.id == "test")
    }

    @Test("CompletionKind has all cases")
    func completionKindCases() {
        let kinds: [CompletionSuggestion.CompletionKind] = [
            .table, .column, .keyword, .function
        ]
        #expect(kinds.count == 4)
    }

    @Test("CompletionKind is Equatable")
    func completionKindIsEquatable() {
        #expect(CompletionSuggestion.CompletionKind.table == .table)
        #expect(CompletionSuggestion.CompletionKind.table != .column)
    }
}
