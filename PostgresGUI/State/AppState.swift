//
//  AppState.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI

@Observable
@MainActor
class AppState {
    // MARK: - Composed State Managers

    let navigation: NavigationState
    let connection: ConnectionState
    let query: QueryState

    // MARK: - Services

    private let tableMetadataService: TableMetadataServiceProtocol

    // MARK: - Tab Manager (for caching query results)

    weak var tabManager: TabManager?

    // MARK: - Debounce State

    private var schemaSearchPathTask: Task<Void, Never>?
    private var tableQueryTask: Task<Void, Never>?
    private var tableQueryRequestId: Int = 0

    // MARK: - Initialization

    init(
        navigation: NavigationState? = nil,
        connection: ConnectionState? = nil,
        query: QueryState? = nil,
        tableMetadataService: TableMetadataServiceProtocol? = nil
    ) {
        self.navigation = navigation ?? NavigationState()
        self.connection = connection ?? ConnectionState()
        self.query = query ?? QueryState()
        self.tableMetadataService = tableMetadataService ?? TableMetadataService()
    }

    // MARK: - Convenience Methods

    func showConnectionForm() {
        navigation.showConnectionForm()
    }

    // MARK: - Query Execution

    /// Request a table query and cancel any in-flight table query task.
    @MainActor
    func requestTableQuery(for table: TableInfo, limit: Int? = nil) {
        tableQueryTask?.cancel()
        tableQueryRequestId += 1
        let requestId = tableQueryRequestId

        tableQueryTask = Task { @MainActor in
            guard !Task.isCancelled else { return }
            connection.selectedTable = table
            await executeTableQueryInternal(for: table, limit: limit, requestId: requestId)
        }
    }

    /// Centralized query execution to prevent race conditions when rapidly switching tables
    /// - Parameters:
    ///   - table: The table to query
    ///   - limit: Optional row limit. If nil, uses pagination (rowsPerPage). If specified, uses that exact limit with no pagination.
    @MainActor
    func executeTableQuery(for table: TableInfo, limit: Int? = nil) async {
        tableQueryTask?.cancel()
        tableQueryTask = nil
        tableQueryRequestId += 1
        let requestId = tableQueryRequestId
        await executeTableQueryInternal(for: table, limit: limit, requestId: requestId)
    }

    @MainActor
    private func executeTableQueryInternal(for table: TableInfo, limit: Int?, requestId: Int) async {
        // Capture context to verify nothing changed after async operations
        // This prevents stale query results when user switches table, database, or connection
        let tableId = table.id
        let databaseId = connection.selectedDatabase?.id
        let connectionId = connection.currentConnection?.id

        let queryService = QueryService(
            databaseService: connection.databaseService,
            queryState: query
        )

        // Set loading state
        query.startQueryExecution()

        // Determine the limit and pagination mode
        let effectiveLimit: Int
        let isPaginated: Bool
        if let customLimit = limit {
            // Custom limit specified - no pagination
            effectiveLimit = customLimit
            isPaginated = false
            // Reset pagination state for non-paginated queries
            query.currentPage = 0
        } else {
            // Use pagination - fetch +1 to detect if more pages exist
            effectiveLimit = query.rowsPerPage + 1
            isPaginated = true
        }

        // Determine preferred column order (table order) for display
        let preferredColumnOrder = await preferredColumnOrder(for: table)

        // Execute query
        let result = await queryService.executeTableQuery(
            for: table,
            limit: effectiveLimit,
            offset: isPaginated ? calculateOffset(page: query.currentPage, pageSize: query.rowsPerPage) : 0,
            preferredColumnOrder: preferredColumnOrder
        )

        guard requestId == tableQueryRequestId else {
            DebugLog.print("⚠️ [AppState] Query for \(table.name) superseded (newer request), skipping state update")
            return
        }

        // Only update state if context hasn't changed (table, database, AND connection)
        // Prevents stale results when same table name exists in different databases
        guard connection.isQueryContextValid(
            tableId: tableId,
            databaseId: databaseId,
            connectionId: connectionId
        ) else {
            DebugLog.print("⚠️ [AppState] Query for \(table.name) superseded (context changed), skipping state update")
            query.isExecutingQuery = false
            return
        }

        // Update state based on result
        if result.isSuccess {
            if isPaginated {
                // Check if we got more rows than requested (indicates next page exists)
                query.hasNextPage = hasMorePages(fetchedRowCount: result.rows.count, pageSize: query.rowsPerPage)
                // Trim to actual page size
                let trimmedRows = query.hasNextPage ? Array(result.rows.prefix(query.rowsPerPage)) : result.rows
                let trimmedResult = QueryResult.success(
                    rows: trimmedRows,
                    columnNames: result.columnNames,
                    executionTime: result.executionTime
                )
                query.finishQueryExecution(with: trimmedResult)
            } else {
                // Non-paginated: use result as-is
                query.hasNextPage = false
                query.finishQueryExecution(with: result)
            }
            query.isResultsReadOnlyDueToContextMismatch = false

            // Cache results to active tab for restoration on tab switch
            query.cachedResultsTableId = table.id
            tabManager?.updateActiveTabResults(
                results: query.queryResults,
                columnNames: query.queryColumnNames
            )

            // Fetch table metadata (primary keys, column info) for edit/delete operations
            await fetchTableMetadata(for: table)
        } else {
            query.finishQueryExecution(with: result)
        }
    }

    /// Fetch and cache table metadata (primary keys, column info)
    @MainActor
    private func fetchTableMetadata(for table: TableInfo) async {
        _ = await tableMetadataService.fetchAndCacheMetadata(
            for: table,
            connectionState: connection,
            databaseService: connection.databaseService
        )
    }

    /// Resolve column order for a table using cached or freshly fetched metadata
    @MainActor
    func preferredColumnOrder(for table: TableInfo) async -> [String]? {
        if let cachedColumns = connection.getColumnInfo(for: table),
           !cachedColumns.isEmpty {
            return cachedColumns.map { $0.name }
        }

        do {
            let columns = try await connection.databaseService.fetchColumnInfo(
                schema: table.schema,
                table: table.name
            )

            guard connection.isTableStillSelected(table.id) else {
                return nil
            }

            let existingCache = connection.tableMetadataCache[table.id]
            connection.tableMetadataCache[table.id] = (
                primaryKeys: existingCache?.primaryKeys,
                columns: columns
            )

            return columns.map { $0.name }
        } catch {
            DebugLog.print("⚠️ [AppState] Failed to fetch column order for \(table.name): \(error)")
            return nil
        }
    }

    /// Resolve column order based on a table name and current selection
    func preferredColumnOrder(forTableName tableName: String?) async -> [String]? {
        guard let tableName else {
            DebugLog.print("🧭 [AppState] preferredColumnOrder: missing tableName")
            return nil
        }

        if let selectedTable = connection.selectedTable,
           selectedTable.name.caseInsensitiveCompare(tableName) == .orderedSame {
            DebugLog.print("🧭 [AppState] preferredColumnOrder: using selected table \(selectedTable.name)")
            return await preferredColumnOrder(for: selectedTable)
        }

        let matchesByName = connection.tables.filter {
            $0.name.caseInsensitiveCompare(tableName) == .orderedSame
        }

        if matchesByName.isEmpty {
            DebugLog.print("🧭 [AppState] preferredColumnOrder: no table match for \(tableName)")
            return nil
        }

        let scopedMatches: [TableInfo]
        if let selectedSchema = connection.selectedSchema {
            scopedMatches = matchesByName.filter { $0.schema == selectedSchema }
        } else {
            scopedMatches = matchesByName
        }

        let resolvedTable: TableInfo?
        if scopedMatches.count == 1 {
            resolvedTable = scopedMatches[0]
        } else if let publicMatch = scopedMatches.first(where: { $0.schema == "public" }) {
            resolvedTable = publicMatch
        } else {
            resolvedTable = scopedMatches.first
        }

        guard let table = resolvedTable else {
            DebugLog.print("🧭 [AppState] preferredColumnOrder: could not resolve table for \(tableName)")
            return nil
        }

        DebugLog.print("🧭 [AppState] preferredColumnOrder: using resolved table \(table.schema).\(table.name)")
        return await preferredColumnOrder(for: table)
    }

    // MARK: - Schema Context

    /// Set the search_path with debounce to prevent race conditions during rapid tab switching
    func setSchemaSearchPathDebounced(_ schema: String?) {
        schemaSearchPathTask?.cancel()
        schemaSearchPathTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await setSchemaSearchPath(schema)
        }
    }

    /// Set the search_path for query context when a schema is selected
    /// Use `setSchemaSearchPathDebounced` for tab switches and user-initiated schema changes
    @MainActor
    func setSchemaSearchPath(_ schema: String?) async {
        guard connection.isConnected else { return }

        // Build search_path: selected schema first, then public as fallback
        let searchPath: String
        if let schema = schema {
            searchPath = schema == "public" ? "public" : "\"\(schema)\", public"
        } else {
            // "All Schemas" selected - reset to default
            searchPath = "public"
        }

        let sql = "SET search_path TO \(searchPath)"
        DebugLog.print("🔧 Setting schema: \(schema ?? "nil") → SQL: \(sql)")

        do {
            _ = try await connection.databaseService.executeQuery(sql)
            connection.schemaError = nil
        } catch {
            DebugLog.print("❌ Failed to set search_path: \(error)")
            connection.schemaError = "Failed to set schema context: \(error.localizedDescription)"
        }
    }

    // MARK: - Cleanup

    /// Clean up resources when window is closing
    func cleanupOnWindowClose() async {
        guard connection.isConnected else { return }

        DebugLog.print("🧹 Window closing, cleaning up...")

        // Cancel any pending queries
        query.cleanup()
        tableQueryTask?.cancel()

        // Disconnect and reset connection state
        await connection.cleanupOnWindowClose()

        DebugLog.print("✅ Cleanup completed")
    }
}
