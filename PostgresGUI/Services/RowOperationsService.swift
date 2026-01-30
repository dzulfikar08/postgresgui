//
//  RowOperationsService.swift
//  PostgresGUI
//
//  Created by ghazi on 12/17/25.
//

import Foundation

/// Service for handling row operations (delete, update, validation)
@MainActor
class RowOperationsService: RowOperationsServiceProtocol {

    // MARK: - Row Validation

    /// Validate that rows are selected and return them
    func validateRowSelection(
        selectedRowIDs: Set<UUID>,
        queryResults: [TableRow]
    ) -> Result<[TableRow], RowOperationError> {
        let selectedRows = queryResults.filter { selectedRowIDs.contains($0.id) }

        guard !selectedRows.isEmpty else {
            return .failure(.noRowsSelected)
        }

        return .success(selectedRows)
    }

    // MARK: - Metadata Management

    /// Ensure table has required metadata (primary keys and column info)
    /// Returns updated table with metadata populated
    func ensureTableMetadata(
        table: TableInfo,
        databaseService: DatabaseServiceProtocol
    ) async -> Result<TableInfo, RowOperationError> {
        var updatedTable = table

        // Fetch primary keys if not already cached
        if updatedTable.primaryKeyColumns == nil {
            do {
                let pkColumns = try await databaseService.fetchPrimaryKeyColumns(
                    schema: updatedTable.schema,
                    table: updatedTable.name
                )
                updatedTable.primaryKeyColumns = pkColumns
            } catch {
                return .failure(.metadataFetchFailed(error.localizedDescription))
            }
        }

        // Fetch column info if not already cached
        if updatedTable.columnInfo == nil {
            do {
                let columnInfo = try await databaseService.fetchColumnInfo(
                    schema: updatedTable.schema,
                    table: updatedTable.name
                )
                updatedTable.columnInfo = columnInfo
            } catch {
                return .failure(.metadataFetchFailed(error.localizedDescription))
            }
        }

        return .success(updatedTable)
    }

    // MARK: - Delete Operations

    /// Delete rows from a table
    func deleteRows(
        table: TableInfo,
        rows: [TableRow],
        databaseService: DatabaseServiceProtocol
    ) async -> Result<Void, RowOperationError> {
        // Validate primary keys exist
        guard let pkColumns = table.primaryKeyColumns, !pkColumns.isEmpty else {
            return .failure(.noPrimaryKey)
        }

        // Perform delete
        do {
            try await databaseService.deleteRows(
                schema: table.schema,
                table: table.name,
                primaryKeyColumns: pkColumns,
                rows: rows
            )
            return .success(())
        } catch {
            return .failure(.deleteFailed(error.localizedDescription))
        }
    }

    // MARK: - Update Operations

    /// Update a row in a table
    func updateRow(
        table: TableInfo,
        originalRow: TableRow,
        updatedValues: [String: RowEditValue],
        databaseService: DatabaseServiceProtocol
    ) async -> Result<TableRow, RowOperationError> {
        // Validate primary keys exist
        guard let pkColumns = table.primaryKeyColumns, !pkColumns.isEmpty else {
            return .failure(.noPrimaryKey)
        }

        // Perform update
        do {
            try await databaseService.updateRow(
                schema: table.schema,
                table: table.name,
                primaryKeyColumns: pkColumns,
                originalRow: originalRow,
                updatedValues: updatedValues
            )

            // Return updated row
            let updatedRowValues = updatedValues.reduce(into: [String: String?]()) { result, entry in
                switch entry.value {
                case .value(let stringValue):
                    result[entry.key] = stringValue
                case .null:
                    result[entry.key] = nil
                }
            }
            let updatedRow = TableRow(values: updatedRowValues)
            return .success(updatedRow)
        } catch {
            return .failure(.updateFailed(error.localizedDescription))
        }
    }
}
