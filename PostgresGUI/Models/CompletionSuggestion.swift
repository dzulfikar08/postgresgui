//
//  CompletionSuggestion.swift
//  PostgresGUI
//
//  Auto-completion suggestion model
//

import Foundation

/// A single auto-completion suggestion
struct CompletionSuggestion: Identifiable, Equatable {
    /// The text to insert when this suggestion is selected
    let text: String

    /// The text to display in the completion popup (may include type info)
    let displayText: String

    /// The kind of completion
    let kind: CompletionKind

    /// Higher scores appear first in the list
    let relevanceScore: Int

    /// Identifier for Identifiable conformance
    var id: String { text }

    /// The type/kind of completion
    enum CompletionKind: String, Equatable {
        case table
        case column
        case keyword
        case function
    }
}
