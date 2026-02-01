//
//  QueryServiceProtocol.swift
//  PostgresGUI
//
//  Created by ghazi on 12/17/25.
//

import Foundation

/// Protocol for query execution operations
@MainActor
protocol QueryServiceProtocol {
    /// Execute a SQL query
    /// - Parameter sql: The SQL query to execute
    /// - Returns: QueryResult with rows, columns, and timing
    func executeQuery(_ sql: String, preferredColumnOrder: [String]?) async -> QueryResult

    /// Execute a table query with pagination
    /// - Parameters:
    ///   - table: The table to query
    ///   - limit: Maximum number of rows to return
    ///   - offset: Number of rows to skip
    /// - Returns: QueryResult with rows, columns, and timing
    func executeTableQuery(
        for table: TableInfo,
        limit: Int,
        offset: Int,
        preferredColumnOrder: [String]?
    ) async -> QueryResult

    /// Cancel the currently running query
    func cancelCurrentQuery()
}
