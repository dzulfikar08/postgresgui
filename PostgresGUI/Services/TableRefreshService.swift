//
//  TableRefreshService.swift
//  PostgresGUI
//
//  Centralized service for table loading and refresh operations.
//  Eliminates duplicate loadTables logic across views.
//

import Foundation

/// Service for loading and refreshing table lists
@MainActor
final class TableRefreshService: TableRefreshServiceProtocol {
    private let keychainService: KeychainServiceProtocol

    init(keychainService: KeychainServiceProtocol? = nil) {
        self.keychainService = keychainService ?? KeychainServiceImpl()
    }

    /// Loads tables for a database, reconnecting if necessary.
    /// - Parameters:
    ///   - database: The database to load tables from
    ///   - connection: The connection profile to use
    ///   - appState: The app state to update
    func loadTables(
        for database: DatabaseInfo,
        connection: ConnectionProfile,
        appState: AppState
    ) async {
        // Only clear loading state if we're still the active request for this database
        defer {
            if appState.connection.selectedDatabase?.id == database.id {
                appState.connection.isLoadingTables = false
            }
        }

        guard !Task.isCancelled else { return }

        // Verify this is still the selected database before any work
        guard appState.connection.selectedDatabase?.id == database.id else { return }

        // Extract connection values before async boundaries (Swift 6 Sendable compliance)
        let connectionId = connection.id
        let host = connection.host
        let port = connection.port
        let username = connection.username
        let sslMode = connection.sslModeEnum

        do {
            // Reconnect if not connected to target database
            if appState.connection.databaseService.connectedDatabase != database.name {
                let password = try keychainService.getPassword(for: connectionId) ?? ""
                try await withDatabaseTimeout {
                    try await appState.connection.databaseService.connect(
                        host: host,
                        port: port,
                        username: username,
                        password: password,
                        database: database.name,
                        sslMode: sslMode
                    )
                }
            }

            guard !Task.isCancelled else { return }

            // Verify still selected after reconnect
            guard appState.connection.selectedDatabase?.id == database.id else { return }

            let tables = try await withDatabaseTimeout {
                try await appState.connection.databaseService.fetchTables(database: database.name)
            }

            let schemas = try await withDatabaseTimeout {
                try await appState.connection.databaseService.fetchSchemas(database: database.name)
            }

            // Final check before writing - prevent stale data from overwriting newer results
            guard !Task.isCancelled,
                  appState.connection.selectedDatabase?.id == database.id else { return }

            appState.connection.tables = tables
            appState.connection.schemas = schemas
            appState.connection.selectedSchema = nil  // Reset schema filter on database change
            await appState.setSchemaSearchPath(nil)  // Reset search_path to default
        } catch is CancellationError {
            // Silently ignore cancellation
        } catch ConnectionError.connectionCancelled {
            // Silently ignore - superseded by newer request
        } catch {
            // Only write error state if still the active request
            guard appState.connection.selectedDatabase?.id == database.id else { return }
            DebugLog.print("❌ [TableRefreshService] Error loading tables: \(error)")
            appState.connection.tables = []
            appState.connection.tableLoadingError = error
            // Show alert for timeout errors
            if DatabaseError.isTimeout(error) {
                appState.connection.showTableLoadingTimeoutAlert = true
            }
        }
    }

    /// Refreshes databases list and, when selected, tables/schemas for current database.
    /// - Parameter appState: The app state to update
    func refresh(appState: AppState) async {
        guard appState.connection.currentConnection != nil,
              appState.connection.databaseService.isConnected else {
            DebugLog.print("⚠️ [TableRefreshService] Refresh skipped: no active connected context")
            return
        }

        let refreshStart = Date()
        let selectedDatabaseAtStart = appState.connection.selectedDatabase?.name ?? "nil"
        let connectedDatabaseAtStart = appState.connection.databaseService.connectedDatabase ?? "nil"
        DebugLog.print(
            "🔄 [TableRefreshService] Refresh started " +
            "(selectedDB: \(selectedDatabaseAtStart), connectedDB: \(connectedDatabaseAtStart))"
        )

        appState.connection.isLoadingTables = true
        appState.connection.tableLoadingError = nil
        defer {
            let totalDuration = Date().timeIntervalSince(refreshStart)
            DebugLog.print(
                "🏁 [TableRefreshService] Refresh ended in \(String(format: "%.3f", totalDuration))s " +
                "(selectedDB: \(appState.connection.selectedDatabase?.name ?? "nil"), " +
                "databases: \(appState.connection.databases.count), tables: \(appState.connection.tables.count))"
            )
            appState.connection.isLoadingTables = false
        }

        // Refresh databases
        var refreshedDatabases: [DatabaseInfo]?
        let databasesFetchStart = Date()
        DebugLog.print("🔄 [TableRefreshService] Fetching databases...")
        do {
            let databases = try await withDatabaseTimeout {
                try await appState.connection.databaseService.fetchDatabases()
            }
            guard !Task.isCancelled else { return }
            refreshedDatabases = databases
            appState.connection.databases = databases
            appState.connection.databasesVersion += 1
            let databasesFetchDuration = Date().timeIntervalSince(databasesFetchStart)
            DebugLog.print(
                "✅ [TableRefreshService] Fetched \(databases.count) databases in " +
                "\(String(format: "%.3f", databasesFetchDuration))s"
            )
        } catch is CancellationError {
            // Silently ignore cancellation
            let databasesFetchDuration = Date().timeIntervalSince(databasesFetchStart)
            DebugLog.print(
                "⚠️ [TableRefreshService] Refresh cancelled while fetching databases " +
                "after \(String(format: "%.3f", databasesFetchDuration))s"
            )
            return
        } catch ConnectionError.connectionCancelled {
            // Silently ignore - superseded by newer refresh
            let databasesFetchDuration = Date().timeIntervalSince(databasesFetchStart)
            DebugLog.print(
                "⚠️ [TableRefreshService] Refresh superseded during database fetch " +
                "after \(String(format: "%.3f", databasesFetchDuration))s"
            )
            return
        } catch {
            let databasesFetchDuration = Date().timeIntervalSince(databasesFetchStart)
            DebugLog.print(
                "❌ [TableRefreshService] Error refreshing databases after " +
                "\(String(format: "%.3f", databasesFetchDuration))s: \(error)"
            )
        }

        guard !Task.isCancelled else { return }

        // If no selected database, a database-list refresh is sufficient.
        guard let selectedDatabase = appState.connection.selectedDatabase else {
            DebugLog.print("ℹ️ [TableRefreshService] No selected database, stopping after database list refresh")
            return
        }

        // If selected database no longer exists, clear dependent UI state.
        if let refreshedDatabases,
           !refreshedDatabases.contains(where: { $0.id == selectedDatabase.id }) {
            DebugLog.print(
                "⚠️ [TableRefreshService] Selected database '\(selectedDatabase.name)' " +
                "no longer exists after refresh; clearing selection"
            )
            await clearSelectionForMissingDatabase(appState: appState)
            return
        }

        // Re-bind selected database to refreshed instance (keeps metadata like tableCount in sync).
        if let refreshedDatabase = refreshedDatabases?.first(where: { $0.id == selectedDatabase.id }) {
            appState.connection.selectedDatabase = refreshedDatabase
        }

        let databaseName = appState.connection.selectedDatabase?.name ?? selectedDatabase.name
        let selectedDatabaseId = appState.connection.selectedDatabase?.id ?? selectedDatabase.id

        // Refresh tables and schemas
        let tablesAndSchemasFetchStart = Date()
        DebugLog.print("🔄 [TableRefreshService] Fetching tables/schemas for '\(databaseName)'...")
        do {
            let tables = try await withDatabaseTimeout {
                try await appState.connection.databaseService.fetchTables(database: databaseName)
            }

            let schemas = try await withDatabaseTimeout {
                try await appState.connection.databaseService.fetchSchemas(database: databaseName)
            }

            // Final check before writing
            guard !Task.isCancelled,
                  appState.connection.selectedDatabase?.id == selectedDatabaseId else {
                DebugLog.print(
                    "⚠️ [TableRefreshService] Ignoring stale tables/schemas refresh for '\(databaseName)' " +
                    "(selection changed)"
                )
                return
            }

            appState.connection.tables = tables
            appState.connection.schemas = schemas
            pruneStaleTableMetadataCache(appState: appState, refreshedTables: tables)
            updateSelectedTable(appState: appState)
            let tablesAndSchemasFetchDuration = Date().timeIntervalSince(tablesAndSchemasFetchStart)
            DebugLog.print(
                "✅ [TableRefreshService] Fetched \(tables.count) tables and \(schemas.count) schemas for " +
                "'\(databaseName)' in \(String(format: "%.3f", tablesAndSchemasFetchDuration))s"
            )

            if let selectedSchema = appState.connection.selectedSchema,
               !schemas.contains(selectedSchema) {
                DebugLog.print(
                    "ℹ️ [TableRefreshService] Selected schema '\(selectedSchema)' no longer exists; resetting search_path"
                )
                appState.connection.selectedSchema = nil
                await appState.setSchemaSearchPath(nil)
            }
        } catch is CancellationError {
            // Silently ignore cancellation
            let tablesAndSchemasFetchDuration = Date().timeIntervalSince(tablesAndSchemasFetchStart)
            DebugLog.print(
                "⚠️ [TableRefreshService] Refresh cancelled while fetching tables/schemas for " +
                "'\(databaseName)' after \(String(format: "%.3f", tablesAndSchemasFetchDuration))s"
            )
            return
        } catch ConnectionError.connectionCancelled {
            // Silently ignore - superseded by newer refresh
            let tablesAndSchemasFetchDuration = Date().timeIntervalSince(tablesAndSchemasFetchStart)
            DebugLog.print(
                "⚠️ [TableRefreshService] Refresh superseded while fetching tables/schemas for " +
                "'\(databaseName)' after \(String(format: "%.3f", tablesAndSchemasFetchDuration))s"
            )
            return
        } catch {
            guard appState.connection.selectedDatabase?.id == selectedDatabaseId else {
                DebugLog.print(
                    "⚠️ [TableRefreshService] Ignoring tables/schemas error for stale refresh of '\(databaseName)'"
                )
                return
            }
            let tablesAndSchemasFetchDuration = Date().timeIntervalSince(tablesAndSchemasFetchStart)
            DebugLog.print("❌ [TableRefreshService] Error refreshing tables: \(error)")
            DebugLog.print(
                "❌ [TableRefreshService] Tables/schemas refresh failed for '\(databaseName)' after " +
                "\(String(format: "%.3f", tablesAndSchemasFetchDuration))s"
            )
            appState.connection.tables = []
            appState.connection.selectedTable = nil
            appState.connection.tableLoadingError = error
            // Show alert for timeout errors
            if DatabaseError.isTimeout(error) {
                appState.connection.showTableLoadingTimeoutAlert = true
            }
        }
    }

    private func clearSelectionForMissingDatabase(appState: AppState) async {
        let hadSchemaSelection = appState.connection.selectedSchema != nil
        appState.connection.selectedDatabase = nil
        appState.connection.selectedTable = nil
        appState.connection.tables = []
        appState.connection.schemas = []
        appState.connection.selectedSchema = nil
        appState.connection.tableMetadataCache = [:]
        if hadSchemaSelection {
            await appState.setSchemaSearchPath(nil)
        }
    }

    private func pruneStaleTableMetadataCache(appState: AppState, refreshedTables: [TableInfo]) {
        let previousCount = appState.connection.tableMetadataCache.count
        let validTableIds = Set(refreshedTables.map(\.id))
        appState.connection.tableMetadataCache = appState.connection.tableMetadataCache.filter {
            validTableIds.contains($0.key)
        }
        let prunedCount = previousCount - appState.connection.tableMetadataCache.count
        if prunedCount > 0 {
            DebugLog.print("🧹 [TableRefreshService] Pruned \(prunedCount) stale table metadata cache entries")
        }
    }

    /// Updates selectedTable reference if it still exists in refreshed list.
    private func updateSelectedTable(appState: AppState) {
        guard let selectedTable = appState.connection.selectedTable,
              let refreshedTable = appState.connection.tables.first(where: { $0.id == selectedTable.id }) else {
            if appState.connection.selectedTable != nil {
                appState.connection.selectedTable = nil
            }
            return
        }

        // Only update if metadata changed
        if refreshedTable != selectedTable {
            appState.connection.selectedTable = refreshedTable
        }
    }
}
