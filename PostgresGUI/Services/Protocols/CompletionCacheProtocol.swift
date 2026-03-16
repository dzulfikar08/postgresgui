//
//  CompletionCacheProtocol.swift
//  PostgresGUI
//
//  Protocol for completion metadata cache
//

import Foundation

@MainActor
protocol CompletionCacheProtocol {
    /// Get all tables for a database
    func getTables(forDatabase databaseId: String) -> [TableInfo]?

    /// Get columns for a specific table
    func getColumns(forTable tableName: String, inSchema schema: String) -> [ColumnInfo]?

    /// Invalidate cache for a specific database
    func invalidateDatabase(_ databaseId: String)

    /// Load metadata for a database
    func loadMetadata(forDatabase databaseId: String) async throws
}
