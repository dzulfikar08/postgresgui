//
//  QueryEditorView.swift
//  PostgresGUI
//
//  Container for query editor. Owns ViewModel and passes data to QueryEditorComponent.
//

import SwiftUI
import SwiftData

struct QueryEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(TabManager.self) private var tabManager
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: QueryEditorViewModel?

    @State private var completionCache: CompletionCache?
    @State private var completionService: SQLCompletionService?
    @State private var tokenizer: SQLTokenizer?

    /// Check if the current query (for this saved query) is executing
    private var isCurrentQueryExecuting: Bool {
        if let currentSavedQueryId = appState.query.currentSavedQueryId {
            if appState.query.executingSavedQueryId == currentSavedQueryId {
                return true
            }
            if appState.query.executingSavedQueryId == nil {
                return appState.query.isExecutingQuery && !appState.query.isExecutingTableQuery
            }
            return false
        }

        // Ad-hoc (unsaved) editor query execution should still show progress.
        return appState.query.isExecutingQuery && !appState.query.isExecutingTableQuery
    }

    var body: some View {
        QueryEditorComponent(
            isExecuting: isCurrentQueryExecuting,
            statusMessage: appState.query.statusMessage,
            lastExecutedAt: appState.query.lastExecutedAt,
            displayedElapsedTime: appState.query.displayedElapsedTime,
            queryText: Binding(
                get: { appState.query.queryText },
                set: { appState.query.queryText = $0 }
            ),
            onRunQuery: {
                Task {
                    await viewModel?.executeQuery()
                }
            },
            onCancelQuery: {
                tabManager.activeTab?.cancelQuery()
                appState.query.cancelCurrentQuery()
            },
            completionService: completionService
        )
        .onAppear {
            viewModel = QueryEditorViewModel(
                appState: appState,
                tabManager: tabManager,
                modelContext: modelContext
            )

            // Initialize completion services
            setupCompletionServices()
        }
        .onChange(of: appState.connection.selectedDatabase) { oldValue, newValue in
            // Reload completion cache when database changes
            Task {
                await loadCompletionMetadata()
            }
        }
        .alert("No Database Selected", isPresented: Binding(
            get: { viewModel?.showNoDatabaseAlert ?? false },
            set: { viewModel?.showNoDatabaseAlert = $0 }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Select a database from the sidebar before running queries.")
        }
        .alert("Failed to Save Query", isPresented: Binding(
            get: { viewModel?.showSaveErrorAlert ?? false },
            set: { viewModel?.showSaveErrorAlert = $0 }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel?.saveErrorMessage ?? "")
        }
        .alert("Query Timed Out", isPresented: Binding(
            get: { appState.query.showTimeoutAlert },
            set: { appState.query.showTimeoutAlert = $0 }
        )) {
            Button("Try Again") {
                appState.query.showTimeoutAlert = false
                appState.query.queryError = nil
                Task {
                    await viewModel?.executeQuery()
                }
            }
            Button("Cancel", role: .cancel) {
                appState.query.showTimeoutAlert = false
            }
        } message: {
            Text("The query took longer than \(Int(Constants.Timeout.databaseOperation)) seconds. The database may be slow or unresponsive.")
        }
        .onChange(of: appState.query.queryText) { _, newText in
            viewModel?.handleQueryTextChange(newText)
        }
    }

    // MARK: - Completion Services Setup

    private func setupCompletionServices() {
        // Get metadata service from database service
        let metadataService = appState.connection.databaseService.metadataService

        tokenizer = SQLTokenizer()
        completionCache = CompletionCache(
            metadataService: metadataService,
            appState: appState
        )
        completionService = SQLCompletionService(
            cache: completionCache!,
            tokenizer: tokenizer!
        )

        Task {
            await loadCompletionMetadata()
        }
    }

    private func loadCompletionMetadata() async {
        guard let databaseId = appState.connection.selectedDatabase?.id else { return }
        try? await completionCache?.loadMetadata(forDatabase: databaseId)
    }
}
