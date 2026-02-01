//
//  DetailContentViewModel.swift
//  PostgresGUI
//
//  Created by ghazi on 12/17/25.
//

import SwiftUI

/// ViewModel for DetailContentView
/// Manages UI state and coordinates business logic for query result operations
@Observable
@MainActor
class DetailContentViewModel {

    // MARK: - Dependencies

    private let appState: AppState
    private let rowOperations: RowOperationsServiceProtocol
    private let queryService: QueryServiceProtocol
    private let tableMetadataService: TableMetadataServiceProtocol

    // MARK: - Modal State

    var showJSONView = false
    var showDeleteConfirmation = false
    var showRowEditor = false

    // MARK: - Editing State

    var rowToEdit: TableRow?
    var editedRowValues: [String: RowEditValue] = [:]

    // MARK: - Error State

    var deleteError: EditabilityReason?
    var editError: EditabilityReason?
    var jsonViewError: String?

    // MARK: - Editability

    /// Determines if current query results can be edited
    var queryEditability: QueryEditability {
        let context = QueryEditabilityContext(
            query: appState.query.queryText,
            sourceTable: appState.connection.selectedTable?.name,
            sourceSchema: appState.connection.selectedTable?.schema
        )
        return determineQueryEditability(context)
    }

    /// Whether results are read-only due to context mismatch
    var isEditingDisabledDueToContextMismatch: Bool {
        appState.query.isResultsReadOnlyDueToContextMismatch
    }

    static let contextMismatchHelpText =
        "Editing disabled because results are from a different connection/database."

    private var contextMismatchReason: EditabilityReason {
        EditabilityReason(
            title: "Read-Only Results",
            body: Self.contextMismatchHelpText
        )
    }

    // MARK: - Initialization

    init(
        appState: AppState,
        rowOperations: RowOperationsServiceProtocol,
        queryService: QueryServiceProtocol,
        tableMetadataService: TableMetadataServiceProtocol? = nil
    ) {
        self.appState = appState
        self.rowOperations = rowOperations
        self.queryService = queryService
        self.tableMetadataService = tableMetadataService ?? TableMetadataService()
    }

    // MARK: - Table Metadata Helpers

    /// Generic helper for fetching metadata and executing a callback
    /// Handles error cases and updates metadata cache
    private func fetchMetadataAndExecute<T>(
        table: TableInfo,
        onSuccess: (TableInfo) -> T
    ) async -> Result<T, RowOperationError> {
        let result = await rowOperations.ensureTableMetadata(
            table: table,
            databaseService: appState.connection.databaseService
        )
        
        switch result {
        case .success(let updatedTable):
            tableMetadataService.updateSelectedTableMetadata(
                connectionState: appState.connection,
                primaryKeys: updatedTable.primaryKeyColumns,
                columnInfo: updatedTable.columnInfo
            )
            return .success(onSuccess(updatedTable))
        case .failure(let error):
            return .failure(error)
        }
    }

    // MARK: - JSON Viewer

    func openJSONView() {
        let result = rowOperations.validateRowSelection(
            selectedRowIDs: appState.query.selectedRowIDs,
            queryResults: appState.query.queryResults
        )

        switch result {
        case .success:
            showJSONView = true
        case .failure(let error):
            jsonViewError = error.localizedDescription
        }
    }

    // MARK: - Delete Operations

    func deleteSelectedRows() {
        DebugLog.print("🗑️ [DetailContentViewModel] Delete button clicked for \(appState.query.selectedRowIDs.count) row(s)")

        if isEditingDisabledDueToContextMismatch {
            deleteError = contextMismatchReason
            return
        }

        // Check if query results are editable (same constraints as edit)
        let editability = queryEditability
        guard editability.isEditable else {
            deleteError = editability.disabledReason
            return
        }

        let resolvedTable: TableInfo? = {
            if let selectedTable = appState.connection.selectedTable {
                return selectedTable
            }

            guard let tableName = editability.tableName else { return nil }
            let candidateTables: [TableInfo]
            if let schemaName = editability.schemaName {
                candidateTables = appState.connection.tables.filter {
                    $0.name == tableName && $0.schema == schemaName
                }
            } else {
                candidateTables = appState.connection.tables.filter { $0.name == tableName }
            }

            return candidateTables.count == 1 ? candidateTables.first : nil
        }()

        guard let selectedTable = resolvedTable else {
            deleteError = EditabilityReason(
                title: "No Table Selected",
                body: "Select a table from the sidebar to delete rows."
            )
            return
        }

        // Validate row selection
        let result = rowOperations.validateRowSelection(
            selectedRowIDs: appState.query.selectedRowIDs,
            queryResults: appState.query.queryResults
        )

        switch result {
        case .success:
            // Check if we have primary keys cached
            if appState.connection.hasPrimaryKeys(for: selectedTable) {
                let pkColumns = appState.connection.getPrimaryKeys(for: selectedTable)
                tableMetadataService.updateSelectedTableMetadata(
                    connectionState: appState.connection,
                    primaryKeys: pkColumns,
                    columnInfo: nil
                )
                showDeleteConfirmation = true
            } else {
                // Fetch primary keys if not cached
                Task {
                    await fetchPrimaryKeysAndShowDeleteDialog(table: selectedTable)
                }
            }
        case .failure(let error):
            deleteError = EditabilityReason(
                title: "Selection Error",
                body: error.localizedDescription
            )
        }
    }

    private func fetchPrimaryKeysAndShowDeleteDialog(table: TableInfo) async {
        let result = await fetchMetadataAndExecute(table: table) { updatedTable in
            updatedTable
        }

        switch result {
        case .success(let updatedTable):
            guard let pkColumns = updatedTable.primaryKeyColumns, !pkColumns.isEmpty else {
                deleteError = EditabilityReason(
                    title: "Can't Identify Row",
                    body: "This table has no primary key. Row deletion requires a way to uniquely identify each row."
                )
                return
            }
            showDeleteConfirmation = true
        case .failure(let error):
            deleteError = EditabilityReason(
                title: "Metadata Error",
                body: error.localizedDescription
            )
        }
    }

    func performDelete() async {
        guard let selectedTable = appState.connection.selectedTable else { return }

        // Get selected rows with their indices for potential rollback
        let deletedIDs = appState.query.selectedRowIDs
        let rowsWithIndices: [(index: Int, row: TableRow)] = appState.query.queryResults
            .enumerated()
            .filter { deletedIDs.contains($0.element.id) }
            .map { (index: $0.offset, row: $0.element) }

        guard !rowsWithIndices.isEmpty else { return }

        // Capture results version before async operation
        let versionBeforeDelete = appState.query.resultsVersion
        // Optimistic UI update: remove rows immediately
        appState.query.queryResults.removeAll { deletedIDs.contains($0.id) }
        appState.query.selectedRowIDs = []

        // Perform backend delete
        let result = await rowOperations.deleteRows(
            table: selectedTable,
            rows: rowsWithIndices.map { $0.row },
            databaseService: appState.connection.databaseService
        )

        let isSuccess: Bool
        switch result {
        case .success:
            isSuccess = true
        case .failure:
            isSuccess = false
        }
        let canRollback = !isSuccess
            ? isSafeToRollback(versionAtOperationStart: versionBeforeDelete, currentVersion: appState.query.resultsVersion)
            : false
        // Rollback on failure (only if results haven't been replaced by a refresh)
        if case .failure(let error) = result {
            if canRollback {
                // Safe to rollback - results haven't changed
                for (index, row) in rowsWithIndices.sorted(by: { $0.index < $1.index }) {
                    let insertIndex = min(index, appState.query.queryResults.count)
                    appState.query.queryResults.insert(row, at: insertIndex)
                }
            }
            deleteError = EditabilityReason(
                title: "Delete Failed",
                body: error.localizedDescription
            )
        }
    }

    // MARK: - Edit Operations

    func editSelectedRows() {
        DebugLog.print("✏️ [DetailContentViewModel] Edit button clicked for \(appState.query.selectedRowIDs.count) row(s)")

        if isEditingDisabledDueToContextMismatch {
            editError = contextMismatchReason
            return
        }

        // Check if query results are editable
        let editability = queryEditability
        guard editability.isEditable else {
            editError = editability.disabledReason
            return
        }

        guard let selectedTable = appState.connection.selectedTable else {
            editError = EditabilityReason(
                title: "No Table Selected",
                body: "Select a table from the sidebar to edit rows."
            )
            return
        }

        // Validate we have column names
        guard appState.query.queryColumnNames != nil else {
            editError = EditabilityReason(
                title: "No Results",
                body: "No query results available to edit."
            )
            return
        }

        // Validate row selection and get first row
        let result = rowOperations.validateRowSelection(
            selectedRowIDs: appState.query.selectedRowIDs,
            queryResults: appState.query.queryResults
        )

        switch result {
        case .success(let selectedRows):
            // Check if multiple rows are selected
            if selectedRows.count > 1 {
                editError = EditabilityReason(
                    title: "Multiple Rows Selected",
                    body: "Please select only one row to edit at a time."
                )
                return
            }

            guard let rowToEdit = selectedRows.first else {
                editError = EditabilityReason(
                    title: "No Row Selected",
                    body: "Select a row to edit."
                )
                return
            }

            // Check if we have required metadata cached
            let pkColumns = appState.connection.getPrimaryKeys(for: selectedTable)
            let colInfo = appState.connection.getColumnInfo(for: selectedTable)

            if let pkColumns = pkColumns, !pkColumns.isEmpty, colInfo != nil {
                tableMetadataService.updateSelectedTableMetadata(
                    connectionState: appState.connection,
                    primaryKeys: pkColumns,
                    columnInfo: colInfo
                )
                self.rowToEdit = rowToEdit
                showRowEditor = true
            } else {
                // Fetch metadata if not cached
                Task {
                    await fetchMetadataAndShowEditor(table: selectedTable, row: rowToEdit)
                }
            }
        case .failure(let error):
            editError = EditabilityReason(
                title: "Selection Error",
                body: error.localizedDescription
            )
        }
    }

    private func fetchMetadataAndShowEditor(table: TableInfo, row: TableRow) async {
        let result = await fetchMetadataAndExecute(table: table) { updatedTable in
            updatedTable
        }

        switch result {
        case .success(let updatedTable):
            guard let pkColumns = updatedTable.primaryKeyColumns, !pkColumns.isEmpty,
                  let _ = updatedTable.columnInfo else {
                editError = EditabilityReason(
                    title: "Can't Identify Row",
                    body: "This table has no primary key. Row editing requires a way to uniquely identify each row."
                )
                return
            }
            self.rowToEdit = row
            showRowEditor = true
        case .failure(let error):
            editError = EditabilityReason(
                title: "Metadata Error",
                body: error.localizedDescription
            )
        }
    }

    func saveEditedRow(originalRow: TableRow, updatedValues: [String: RowEditValue]) async throws {
        DebugLog.print("🟡 [DetailContentViewModel.saveEditedRow] Received updatedValues: \(updatedValues)")
        DebugLog.print("  updatedValues count: \(updatedValues.count)")

        guard let selectedTable = appState.connection.selectedTable else {
            throw RowOperationError.noTableSelected
        }

        // Perform update
        let result = await rowOperations.updateRow(
            table: selectedTable,
            originalRow: originalRow,
            updatedValues: updatedValues,
            databaseService: appState.connection.databaseService
        )

        switch result {
        case .success(let updatedRow):
            // Update the row in the UI
            if let index = appState.query.queryResults.firstIndex(where: { $0.id == originalRow.id }) {
                appState.query.queryResults[index] = updatedRow

                // Update selection to use the new row's ID
                appState.query.selectedRowIDs.remove(originalRow.id)
                appState.query.selectedRowIDs.insert(updatedRow.id)
            }
        case .failure(let error):
            throw error
        }
    }

    // MARK: - Query Refresh

    func refreshQuery() async {
        DebugLog.print("🔄 [DetailContentViewModel] Refresh button clicked")

        // Set loading state FIRST to prevent empty state flicker
        appState.query.startQueryExecution()
        appState.query.clearQueryResults()

        // Execute query
        let tableName = QueryTypeDetector.extractTableName(appState.query.queryText)
        let preferredColumnOrder = await appState.preferredColumnOrder(forTableName: tableName)
        let result = await queryService.executeQuery(
            appState.query.queryText,
            preferredColumnOrder: preferredColumnOrder
        )

        // Update state based on result
        if result.isSuccess {
            appState.query.resultsVersion += 1
        }
        appState.query.finishQueryExecution(with: result)
        if result.isSuccess {
            appState.query.isResultsReadOnlyDueToContextMismatch = false
        }

        if result.isSuccess {
            DebugLog.print("✅ [DetailContentViewModel] Query executed successfully, showing results")
        } else {
            DebugLog.print("❌ [DetailContentViewModel] Query execution failed: \(result.error?.localizedDescription ?? "unknown")")
        }
    }
}
