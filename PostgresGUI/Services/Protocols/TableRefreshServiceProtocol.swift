//
//  TableRefreshServiceProtocol.swift
//  PostgresGUI
//
//  Protocol abstraction for table loading and refresh operations.
//  Enables dependency injection and testability.
//

import Foundation

/// Protocol defining table loading and refresh operations
@MainActor
protocol TableRefreshServiceProtocol {
    /// Loads tables for a database, reconnecting if necessary.
    func loadTables(
        for database: DatabaseInfo,
        connection: ConnectionProfile,
        appState: AppState
    ) async

    /// Refreshes database list when connected; refreshes tables/schemas when a database is selected.
    func refresh(appState: AppState) async
}
