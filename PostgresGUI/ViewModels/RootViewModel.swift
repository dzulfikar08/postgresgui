//
//  RootViewModel.swift
//  PostgresGUI
//
//  Handles app initialization, tab switching, and connection restoration.
//  Uses TabViewModel (in-memory) for safe async operations - never accesses
//  SwiftData TabState directly.
//
//  Created by ghazi on 12/30/25.
//

import Foundation
import SwiftData

@Observable
@MainActor
class RootViewModel {
    // MARK: - Dependencies

    private let appState: AppState
    private let tabManager: TabManager
    private let loadingState: LoadingState
    private let modelContext: ModelContext
    private let keychainService: KeychainServiceProtocol
    private let tableRefreshService: TableRefreshServiceProtocol

    // MARK: - State

    var initializationError: String?

    /// Generation counter for tab switches - used to detect superseded operations
    /// More reliable than Task.isCancelled because state mutations happen synchronously
    private var tabSwitchGeneration: UInt64 = 0

    // MARK: - Initialization

    init(
        appState: AppState,
        tabManager: TabManager,
        loadingState: LoadingState,
        modelContext: ModelContext,
        keychainService: KeychainServiceProtocol? = nil,
        tableRefreshService: TableRefreshServiceProtocol? = nil
    ) {
        self.appState = appState
        self.tabManager = tabManager
        self.loadingState = loadingState
        self.modelContext = modelContext
        let keychain = keychainService ?? KeychainServiceImpl()
        self.keychainService = keychain
        self.tableRefreshService = tableRefreshService ?? TableRefreshService(keychainService: keychain)
    }

    // MARK: - App Initialization

    /// Initialize the app: restore tabs, connect to last connection, load databases/tables
    func initializeApp(connections: [ConnectionProfile]) async {
        DebugLog.print("🚀 [RootViewModel] initializeApp started")

        // Initialize tab manager with model context
        loadingState.setPhase(.restoringTabs)
        tabManager.initialize(with: modelContext)

        // Wait for SwiftData to load connections
        try? await Task.sleep(nanoseconds: 0.1.nanoseconds)

        DebugLog.print("🚀 [RootViewModel] connections count: \(connections.count)")

        // If no connections exist, skip to ready state (welcome screen will show)
        guard !connections.isEmpty else {
            DebugLog.print("🚀 [RootViewModel] No connections, showing welcome")
            loadingState.setReady()
            return
        }

        // Get active tab's connection (use TabViewModel, not TabState)
        guard let activeTab = tabManager.activeTab,
              let connectionId = activeTab.connectionId,
              let connection = connections.first(where: { $0.id == connectionId }) else {
            DebugLog.print("🚀 [RootViewModel] No connection to restore, finishing")
            loadingState.setReady()
            return
        }

        DebugLog.print("🚀 [RootViewModel] Restoring connection: \(connection.displayName)")

        // Restore query text and saved query selection from active tab
        restoreQueryStateFromTab(activeTab)

        // Connect to database
        loadingState.setPhase(.connectingToDatabase)
        let connectionService = ConnectionService(
            appState: appState,
            keychainService: keychainService
        )

        let result = await connectionService.connect(to: connection, saveAsLast: true)

        if case .failure(let error) = result {
            initializationError = PostgresError.extractDetailedMessage(error)
            loadingState.setReady()
            return
        }

        // Load databases
        loadingState.setPhase(.loadingDatabases)
        do {
            appState.connection.databases = try await appState.connection.databaseService.fetchDatabases()
            appState.connection.databasesVersion += 1
        } catch {
            DebugLog.print("Failed to load databases: \(error)")
            initializationError = PostgresError.extractDetailedMessage(error)
            loadingState.setReady()
            return
        }

        // Restore database selection from active tab
        if let databaseName = activeTab.databaseName,
           let database = appState.connection.databases.first(where: { $0.name == databaseName }) {
            appState.connection.selectedDatabase = database

            // Load tables
            loadingState.setPhase(.loadingTables)
            await loadTables(for: database, connection: connection)

            // Restore table selection and cached results from tab
            restoreTableSelectionFromTab(activeTab)
            restoreCachedResultsFromTab(activeTab)
        }

        loadingState.setReady()
    }

    // MARK: - Tab Change Handling

    /// Check if this tab switch is still the current one
    /// Returns false if a newer tab switch has started (this one is superseded)
    private func isTabSwitchCurrent(_ generation: UInt64) -> Bool {
        generation == tabSwitchGeneration
    }

    /// Handle tab switch: restore query state, connect if needed, load tables
    /// Now takes TabViewModel which is safe to access (not tied to SwiftData)
    func handleTabChange(_ tab: TabViewModel?, connections: [ConnectionProfile]) async {
        guard let tab = tab, !tab.isPendingDeletion else { return }

        // Increment generation to invalidate any in-flight tab switches
        tabSwitchGeneration &+= 1
        let myGeneration = tabSwitchGeneration

        // Capture tab ID for validity checks after async operations
        let tabId = tab.id

        DebugLog.print("📑 [RootViewModel] Tab changed to: \(tabId) (generation: \(myGeneration))")

        // Set flag to prevent result-clearing during tab restore
        appState.query.isRestoringFromTab = true

        // Restore query text and saved query selection
        let previousQueryText = appState.query.queryText
        restoreQueryStateFromTab(tab)
        if previousQueryText != tab.queryText {
            DebugLog.print("📝 [RootViewModel] queryText changed from: \"\(previousQueryText.prefix(30))...\" to: \"\(tab.queryText.prefix(30))...\" (tab restore)")
        }

        // Restore cached results from tab (or clear if none)
        restoreCachedResultsFromTab(tab)

        // If tab has no connection, just clear and return
        guard let connectionId = tab.connectionId,
              let connection = connections.first(where: { $0.id == connectionId }) else {
            clearConnectionState()
            appState.query.isRestoringFromTab = false
            return
        }

        // Check if we're switching to the same connection AND database
        let sameConnection = appState.connection.currentConnection?.id == connectionId
        let sameDatabase = appState.connection.selectedDatabase?.name == tab.databaseName
        let isConnected = appState.connection.databaseService.isConnected

        if sameConnection && sameDatabase && isConnected && !appState.connection.tables.isEmpty {
            // Fast path: same connection and database, just restore table selection
            DebugLog.print("📑 [RootViewModel] Tab switch - same connection/database, restoring table selection only")
            restoreTableSelectionFromTab(tab)
            // Yield to let SwiftUI process onChange before clearing flag
            await Task.yield()
            appState.query.isRestoringFromTab = false
            return
        }

        // Set loading state and clear tables for full reload
        appState.connection.isLoadingTables = true
        appState.connection.selectedTable = nil
        appState.connection.tables = []

        // Connect if different connection or not connected
        if !sameConnection || !isConnected {
            DebugLog.print("🔌 [RootViewModel] Tab switch requires connection to: \(connection.displayName)")
            let connectionService = ConnectionService(
                appState: appState,
                keychainService: keychainService
            )

            let result = await connectionService.connect(to: connection, saveAsLast: false)

            // Check if superseded after async operation
            guard isTabSwitchCurrent(myGeneration) else {
                DebugLog.print("📑 [RootViewModel] Tab switch superseded after connection (gen \(myGeneration) vs \(tabSwitchGeneration))")
                appState.query.isRestoringFromTab = false
                return
            }

            // Check if tab was deleted during connection
            guard tabManager.isTabValid(tabId) else {
                DebugLog.print("📑 [RootViewModel] Tab was deleted during connection, aborting")
                appState.connection.isLoadingTables = false
                appState.query.isRestoringFromTab = false
                return
            }

            if case .failure(let error) = result {
                // Check if this is a cancellation error (superseded by newer connection)
                if case ConnectionError.connectionCancelled = error {
                    DebugLog.print("📑 [RootViewModel] Tab switch connection was cancelled (superseded)")
                    appState.connection.isLoadingTables = false
                    appState.query.isRestoringFromTab = false
                    return
                }
                DebugLog.print("❌ [RootViewModel] Tab switch connection failed: \(error)")
                initializationError = PostgresError.extractDetailedMessage(error)
                appState.connection.isLoadingTables = false
                appState.query.isRestoringFromTab = false
                return
            }
            DebugLog.print("✅ [RootViewModel] Tab switch connection successful")
        } else {
            DebugLog.print("🔌 [RootViewModel] Tab switch reusing existing connection to: \(connection.displayName)")
        }

        // Check if superseded before database fetch
        guard isTabSwitchCurrent(myGeneration) else {
            DebugLog.print("📑 [RootViewModel] Tab switch superseded before database fetch (gen \(myGeneration) vs \(tabSwitchGeneration))")
            appState.query.isRestoringFromTab = false
            return
        }

        // Load databases
        do {
            appState.connection.databases = try await appState.connection.databaseService.fetchDatabases()
            appState.connection.databasesVersion += 1
        } catch {
            // Check if superseded - don't show error for race conditions
            guard isTabSwitchCurrent(myGeneration) else {
                DebugLog.print("📑 [RootViewModel] Tab switch superseded during database fetch (gen \(myGeneration) vs \(tabSwitchGeneration))")
                appState.query.isRestoringFromTab = false
                return
            }
            // Check for notConnected which typically indicates a race condition
            if case ConnectionError.notConnected = error {
                DebugLog.print("📑 [RootViewModel] Tab switch got notConnected (likely superseded)")
                appState.connection.isLoadingTables = false
                appState.query.isRestoringFromTab = false
                return
            }
            DebugLog.print("Failed to load databases: \(error)")
            initializationError = PostgresError.extractDetailedMessage(error)
            appState.connection.isLoadingTables = false
            appState.query.isRestoringFromTab = false
            return
        }

        // Check if superseded after database fetch
        guard isTabSwitchCurrent(myGeneration) else {
            DebugLog.print("📑 [RootViewModel] Tab switch superseded after fetching databases (gen \(myGeneration) vs \(tabSwitchGeneration))")
            appState.query.isRestoringFromTab = false
            return
        }

        // Check if tab was deleted during database fetch
        guard tabManager.isTabValid(tabId) else {
            DebugLog.print("📑 [RootViewModel] Tab was deleted during database fetch, aborting")
            appState.connection.isLoadingTables = false
            appState.query.isRestoringFromTab = false
            return
        }

        // Restore database selection (use current tab state, not captured values)
        guard let currentTab = tabManager.tab(by: tabId) else {
            DebugLog.print("📑 [RootViewModel] Tab no longer exists, aborting")
            appState.connection.isLoadingTables = false
            appState.query.isRestoringFromTab = false
            return
        }

        if let databaseName = currentTab.databaseName,
           let database = appState.connection.databases.first(where: { $0.name == databaseName }) {
            appState.connection.selectedDatabase = database
            await loadTables(for: database, connection: connection)

            // Check if superseded after loading tables
            guard isTabSwitchCurrent(myGeneration) else {
                DebugLog.print("📑 [RootViewModel] Tab switch superseded after loading tables (gen \(myGeneration) vs \(tabSwitchGeneration))")
                appState.query.isRestoringFromTab = false
                return
            }

            // Check if tab still valid
            guard let finalTab = tabManager.tab(by: tabId) else {
                DebugLog.print("📑 [RootViewModel] Tab deleted after loading tables, aborting")
                appState.query.isRestoringFromTab = false
                return
            }

            // Restore table selection from tab (after tables are loaded)
            restoreTableSelectionFromTab(finalTab)
            // Yield to let SwiftUI process onChange before clearing flag
            await Task.yield()
            appState.query.isRestoringFromTab = false
        } else {
            // No database selected in tab, stop loading
            appState.connection.isLoadingTables = false
            appState.query.isRestoringFromTab = false
        }
    }

    // MARK: - Tab State Management

    /// Save current state to active tab before switching or closing
    func saveCurrentStateToTab() {
        guard let activeTab = tabManager.activeTab, !activeTab.isPendingDeletion else { return }
        tabManager.updateActiveTab(
            connectionId: activeTab.connectionId,
            databaseName: activeTab.databaseName,
            queryText: appState.query.queryText,
            savedQueryId: appState.query.currentSavedQueryId
        )
    }

    /// Create a new tab inheriting from current
    func createNewTab() {
        saveCurrentStateToTab()
        tabManager.createNewTab(inheritingFrom: tabManager.activeTab)
    }

    /// Close the current tab
    func closeCurrentTab() {
        guard let activeTab = tabManager.activeTab else { return }
        tabManager.closeTab(activeTab)
    }

    // MARK: - Database Selection

    /// Select a database and load its tables
    func selectDatabase(_ database: DatabaseInfo) async {
        guard let connection = appState.connection.currentConnection else { return }

        appState.connection.selectedDatabase = database
        appState.connection.tables = []
        appState.connection.isLoadingTables = true
        appState.connection.selectedTable = nil

        await loadTables(for: database, connection: connection)
    }

    // MARK: - Private Helpers

    private func restoreQueryStateFromTab(_ tab: TabViewModel) {
        appState.query.queryText = tab.queryText
        appState.query.currentSavedQueryId = tab.savedQueryId
        restoreSavedQueryMetadata(for: tab.savedQueryId)
    }

    private func restoreCachedResultsFromTab(_ tab: TabViewModel) {
        DebugLog.print("📊 [RootViewModel] Restoring cached results from tab \(tab.id)")

        // Check for pending deletion before accessing properties
        guard !tab.isPendingDeletion else {
            DebugLog.print("📊 [RootViewModel] Tab is pending deletion, skipping cache restore")
            return
        }


        if let cachedResults = tab.cachedResults {
            appState.query.queryResults = cachedResults
            appState.query.queryColumnNames = tab.cachedColumnNames
            appState.query.showQueryResults = true
            if let schema = tab.selectedTableSchema, let name = tab.selectedTableName {
                appState.query.cachedResultsTableId = "\(schema).\(name)"
            } else {
                appState.query.cachedResultsTableId = nil
            }
            DebugLog.print("📊 [RootViewModel] Restored \(cachedResults.count) cached query results, showQueryResults=true")
        } else {
            DebugLog.print("📊 [RootViewModel] No cached results in tab, clearing")
            appState.query.queryResults = []
            appState.query.queryColumnNames = nil
            appState.query.cachedResultsTableId = nil
        }
    }

    private func restoreTableSelectionFromTab(_ tab: TabViewModel) {
        guard !tab.isPendingDeletion else { return }

        // Restore schema filter
        appState.connection.selectedSchema = tab.selectedSchemaFilter
        appState.setSchemaSearchPathDebounced(tab.selectedSchemaFilter)

        // Restore table selection
        if let tableSchema = tab.selectedTableSchema,
           let tableName = tab.selectedTableName,
           let table = appState.connection.tables.first(where: {
               $0.schema == tableSchema && $0.name == tableName
           }) {
            appState.connection.selectedTable = table
        } else {
            appState.connection.selectedTable = nil
        }
    }

    private func clearConnectionState() {
        appState.connection.currentConnection = nil
        appState.connection.selectedDatabase = nil
        appState.connection.selectedTable = nil
        appState.connection.databases = []
        appState.connection.databasesVersion += 1
        appState.connection.tables = []
        appState.connection.isLoadingTables = false
    }

    private func restoreSavedQueryMetadata(for savedQueryId: UUID?) {
        guard let savedQueryId = savedQueryId else {
            appState.query.currentQueryName = nil
            appState.query.lastSavedAt = nil
            return
        }

        let descriptor = FetchDescriptor<SavedQuery>(
            predicate: #Predicate { $0.id == savedQueryId }
        )
        if let savedQuery = try? modelContext.fetch(descriptor).first {
            appState.query.currentQueryName = savedQuery.name
            appState.query.lastSavedAt = savedQuery.updatedAt
        }
    }

    private func loadTables(for database: DatabaseInfo, connection: ConnectionProfile) async {
        await tableRefreshService.loadTables(
            for: database,
            connection: connection,
            appState: appState
        )
    }
}
