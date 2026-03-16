//
//  SQLContext.swift
//  PostgresGUI
//
//  SQL context types for auto-completion
//

import Foundation

/// The SQL context at the cursor position for auto-completion
enum SQLContext: Equatable, Hashable {
    /// After SELECT keyword - expecting column names
    case selectClause

    /// After FROM/JOIN keywords - expecting table names
    case fromClause

    /// After WHERE keyword - expecting columns and operators
    case whereClause

    /// After schema.table dot notation - expecting column names from that table
    case tableReference

    /// No specific context detected
    case defaultContext
}
