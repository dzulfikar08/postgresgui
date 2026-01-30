//
//  RowOperationsServiceProtocol.swift
//  PostgresGUI
//
//  Created by ghazi on 12/17/25.
//

import Foundation

/// Protocol defining the interface for row operations (delete, update, validate)
@MainActor
protocol RowOperationsServiceProtocol {
    /// Validate that rows are selected and return them
    func validateRowSelection(
        selectedRowIDs: Set<UUID>,
        queryResults: [TableRow]
    ) -> Result<[TableRow], RowOperationError>

    /// Ensure table has required metadata (primary keys and column info)
    /// Returns updated table with metadata populated
    func ensureTableMetadata(
        table: TableInfo,
        databaseService: DatabaseServiceProtocol
    ) async -> Result<TableInfo, RowOperationError>

    /// Delete rows from a table
    func deleteRows(
        table: TableInfo,
        rows: [TableRow],
        databaseService: DatabaseServiceProtocol
    ) async -> Result<Void, RowOperationError>

    /// Update a row in a table
    func updateRow(
        table: TableInfo,
        originalRow: TableRow,
        updatedValues: [String: RowEditValue],
        databaseService: DatabaseServiceProtocol
    ) async -> Result<TableRow, RowOperationError>
}
