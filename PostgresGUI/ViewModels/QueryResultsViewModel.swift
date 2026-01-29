//
//  QueryResultsViewModel.swift
//  PostgresGUI
//
//  Handles table selection, pagination, and result caching.
//  Extracted from QueryResultsView to separate business logic from presentation.
//
//  Created by ghazi on 12/30/25.
//

import Foundation

@Observable
@MainActor
class QueryResultsViewModel {
    // MARK: - Dependencies

    private let appState: AppState
    private let tabManager: TabManager

    // MARK: - State

    private(set) var lastExecutedTableID: String?

    // MARK: - Initialization

    init(appState: AppState, tabManager: TabManager) {
        self.appState = appState
        self.tabManager = tabManager
    }

    // MARK: - Table Selection Handling

    /// Handle table selection changes
    /// Note: Table selection no longer auto-executes queries. Users must use the context menu
    /// to "Show All Rows" or "Show 100 Rows" to view table data.
    func handleTableSelectionChange(oldValue: String?, newValue: String?) {
        let table = appState.connection.selectedTable
        let shouldUseCached = shouldUseCachedResults(
            hasResults: !appState.query.queryResults.isEmpty,
            cachedTableId: appState.query.cachedResultsTableId,
            selectedTableId: newValue
        )

        // Check if we should use cached results for the selected table
        // Clear results when table changes, UNLESS we have cached results for this table
        if shouldClearResultsOnTableChange(
            oldTableId: oldValue,
            newTableId: newValue,
            hasCachedResultsForNewTable: shouldUseCached
        ) {
            appState.query.queryColumnNames = nil
            appState.query.queryError = nil
            appState.query.currentPage = 0
            appState.query.selectedRowIDs = []
            appState.query.queryResults = []
            appState.query.showQueryResults = false
            appState.query.cachedResultsTableId = nil
        }

        // Save table selection to tab
        tabManager.updateActiveTabTableSelection(
            schema: table?.schema,
            name: table?.name
        )

        // Track table selection but do NOT auto-execute query
        // Users must explicitly choose "Show All Rows" or "Show 100 Rows" from context menu
        if let table = table, table.id != lastExecutedTableID {
            lastExecutedTableID = table.id

            // Only restore cached results if they exist for this table
            if shouldUseCached {
                DebugLog.print("📋 [QueryResultsViewModel] Using cached results for table \(table.name)")
            } else {
                DebugLog.print("📋 [QueryResultsViewModel] Table \(table.name) selected - use context menu to view data")
            }
        } else if newValue == nil {
            // Skip clearing if we're restoring from a tab switch
            // (tab restoration handles results separately from table selection)
            guard !appState.query.isRestoringFromTab else {
                DebugLog.print("📋 [QueryResultsViewModel] Table selection nil during tab restore - skipping result clear")
                lastExecutedTableID = nil
                return
            }

            // Clear query results when table selection is cleared (but preserve queryText)
            lastExecutedTableID = nil
            DebugLog.print("📋 [QueryResultsViewModel] Table selection cleared - preserving queryText, clearing results")
            appState.query.showQueryResults = false
            appState.query.queryResults = []
            appState.query.cachedResultsTableId = nil
            // Clear cached results in tab
            tabManager.updateActiveTabResults(results: nil, columnNames: nil)
        }
    }

    // MARK: - Pagination

    /// Go to the previous page of results
    func goToPreviousPage() {
        guard appState.query.currentPage > 0,
              let table = appState.connection.selectedTable else { return }
        appState.query.currentPage -= 1
        appState.query.hasNextPage = true  // We know there's a next page since we came from it
        Task {
            await executeTableQuery(for: table)
        }
    }

    /// Go to the next page of results
    func goToNextPage() {
        guard let table = appState.connection.selectedTable else { return }
        appState.query.currentPage += 1
        Task {
            await executeTableQuery(for: table)
        }
    }

    // MARK: - Private Helpers

    private func executeTableQuery(for table: TableInfo) async {
        await appState.executeTableQuery(for: table)
        // Only update cache tracking if this table is still selected
        // (prevents race condition when rapidly switching tables)
        guard appState.connection.isTableStillSelected(table.id) else { return }
        appState.query.cachedResultsTableId = table.id
        // Cache results to tab for restoration on tab switch
        tabManager.updateActiveTabResults(
            results: appState.query.queryResults,
            columnNames: appState.query.queryColumnNames
        )
    }
}
