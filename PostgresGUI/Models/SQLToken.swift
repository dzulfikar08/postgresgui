//
//  SQLToken.swift
//  PostgresGUI
//
//  SQL token types for parsing
//

import Foundation

/// A lexical token from SQL text
enum SQLToken: Equatable {
    /// SQL keyword (SELECT, FROM, WHERE, etc.)
    case keyword(String)

    /// Identifier (table name, column name, etc.)
    case identifier(String)

    /// Operator (=, <>, LIKE, etc.)
    case `operator`(String)

    /// String literal
    case stringLiteral(String)

    /// Whitespace (spaces, tabs, newlines)
    case whitespace

    /// Dot operator (.)
    case dot

    /// Comma separator (,)
    case comma
}
