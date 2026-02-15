//
//  QueryResultsView.swift
//  PostgresGUI
//
//  Container for query results. Owns ViewModel and passes data to QueryResultsComponent.
//

import SwiftUI

struct QueryResultsView: View {
    @Environment(AppState.self) private var appState
    @Environment(TabManager.self) private var tabManager
    @State private var viewModel: QueryResultsViewModel?
    
    var searchText: String = ""
    var onDeleteKeyPressed: (() -> Void)?
    var onSpaceKeyPressed: (() -> Void)?

    /// Whether the current query (for this saved query) is executing
    private var isCurrentQueryExecuting: Bool {
        appState.query.executingSavedQueryId == appState.query.currentSavedQueryId &&
        appState.query.executingSavedQueryId != nil
    }

    /// Whether a table query is executing for the currently selected table
    private var isExecutingTableQueryForSelectedTable: Bool {
        appState.query.isExecutingTableQuery &&
        appState.query.executingTableQueryTableId == appState.connection.selectedTable?.id
    }

    private var isExecutingResultsLoad: Bool {
        isCurrentQueryExecuting || isExecutingTableQueryForSelectedTable
    }
    
    private var columnNames: [String]? {
        // First try to get column names from stored queryColumnNames (works even for empty results)
        if let columnNames = appState.query.queryColumnNames, !columnNames.isEmpty {
            return columnNames
        }
        return nil
    }

    var body: some View {
        QueryResultsComponent(
            results: appState.query.queryResults,
            columnNames: columnNames,
            searchText: searchText,
            isExecuting: isExecutingResultsLoad,
            errorMessage: appState.query.queryErrorMessage,
            hasExecutedQuery: appState.query.showQueryResults,
            currentPage: appState.query.currentPage,
            hasNextPage: appState.query.hasNextPage,
            tableId: appState.connection.selectedTable?.id,
            selectedRowIDs: Binding(
                get: { appState.query.selectedRowIDs },
                set: { newValue in
                    appState.query.selectedRowIDs = newValue
                }
            ),
            onPreviousPage: {
                viewModel?.goToPreviousPage()
            },
            onNextPage: {
                viewModel?.goToNextPage()
            },
            onDeleteKeyPressed: onDeleteKeyPressed,
            onSpaceKeyPressed: onSpaceKeyPressed
        )
        .onAppear {
            viewModel = QueryResultsViewModel(appState: appState, tabManager: tabManager)
        }
        .onChange(of: appState.connection.selectedTable?.id) { oldValue, newValue in
            viewModel?.handleTableSelectionChange(oldValue: oldValue, newValue: newValue)
        }
    }
}
