//
//  TableMetadataService.swift
//  PostgresGUI
//
//  Service for fetching and caching table metadata (primary keys and column info)
//  Consolidates metadata fetching logic from AppState and DetailContentViewModel
//

import Foundation

/// Service for managing table metadata fetching and caching
@MainActor
final class TableMetadataService: TableMetadataServiceProtocol {

    init() {}

    /// Fetch and cache table metadata (primary keys and column info)
    /// Handles race conditions by checking if table is still selected
    /// - Parameters:
    ///   - table: The table to fetch metadata for
    ///   - connectionState: The connection state to check selection and update cache
    ///   - databaseService: The database service to fetch metadata from
    /// - Returns: Tuple of (primaryKeys, columnInfo) if successfully fetched, nil if table selection changed
    func fetchAndCacheMetadata(
        for table: TableInfo,
        connectionState: ConnectionState,
        databaseService: DatabaseServiceProtocol
    ) async -> (primaryKeys: [String]?, columnInfo: [ColumnInfo]?)? {
        // Store table ID to verify selection hasn't changed
        let tableId = table.id
        let databaseId = connectionState.selectedDatabase?.id
        let connectionId = connectionState.currentConnection?.id

        var primaryKeyColumns: [String]?
        var columnInfo: [ColumnInfo]?

        // Fetch primary key columns if not cached
        if table.primaryKeyColumns == nil {
            do {
                primaryKeyColumns = try await databaseService.fetchPrimaryKeyColumns(
                    schema: table.schema,
                    table: table.name
                )
            } catch {
                DebugLog.print("⚠️ [TableMetadataService] Failed to fetch primary keys: \(error)")
            }
        }

        // Check if user switched tables during primary key fetch
        guard connectionState.isQueryContextValid(
            tableId: tableId,
            databaseId: databaseId,
            connectionId: connectionId
        ) else {
            DebugLog.print("⚠️ [TableMetadataService] Query context changed during metadata fetch, skipping update for \(table.schema).\(table.name)")
            return nil
        }

        // Fetch column info if not cached
        if table.columnInfo == nil {
            do {
                columnInfo = try await databaseService.fetchColumnInfo(
                    schema: table.schema,
                    table: table.name
                )
            } catch {
                DebugLog.print("⚠️ [TableMetadataService] Failed to fetch column info: \(error)")
            }
        }

        // Final check: only update if this table is still selected (prevents race condition)
        guard connectionState.isQueryContextValid(
            tableId: tableId,
            databaseId: databaseId,
            connectionId: connectionId
        ) else {
            DebugLog.print("⚠️ [TableMetadataService] Query context changed during metadata fetch, skipping update for \(table.schema).\(table.name)")
            return nil
        }

        // Only update if we actually fetched new data
        guard primaryKeyColumns != nil || columnInfo != nil else {
            return nil
        }

        // Store in separate metadata cache (doesn't trigger List re-renders)
        let existingCache = connectionState.tableMetadataCache[tableId]
        connectionState.tableMetadataCache[tableId] = (
            primaryKeys: primaryKeyColumns ?? existingCache?.primaryKeys,
            columns: columnInfo ?? existingCache?.columns
        )

        DebugLog.print("✅ [TableMetadataService] Cached metadata for \(table.schema).\(table.name)")

        return (primaryKeys: primaryKeyColumns, columnInfo: columnInfo)
    }

    /// Update the selected table with metadata if not already set
    /// Also updates the metadata cache
    /// - Parameters:
    ///   - connectionState: The connection state containing selectedTable and cache
    ///   - primaryKeys: Optional primary keys to update
    ///   - columnInfo: Optional column info to update
    func updateSelectedTableMetadata(
        connectionState: ConnectionState,
        primaryKeys: [String]? = nil,
        columnInfo: [ColumnInfo]? = nil
    ) {
        guard let selectedTable = connectionState.selectedTable else { return }

        let needsPKUpdate = primaryKeys != nil && selectedTable.primaryKeyColumns == nil
        let needsColInfoUpdate = columnInfo != nil && selectedTable.columnInfo == nil

        guard needsPKUpdate || needsColInfoUpdate else { return }

        var updatedTable = selectedTable
        if needsPKUpdate { updatedTable.primaryKeyColumns = primaryKeys }
        if needsColInfoUpdate { updatedTable.columnInfo = columnInfo }
        connectionState.selectedTable = updatedTable

        // Also update cache
        let existingCache = connectionState.tableMetadataCache[selectedTable.id]
        connectionState.tableMetadataCache[selectedTable.id] = (
            primaryKeys: primaryKeys ?? existingCache?.primaryKeys,
            columns: columnInfo ?? existingCache?.columns
        )
    }
}
