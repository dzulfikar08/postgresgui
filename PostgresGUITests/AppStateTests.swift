//
//  AppStateTests.swift
//  PostgresGUITests
//
//  Unit tests for AppState, including race condition handling.
//

import Foundation
import Testing
@testable import PostgresGUI

// MARK: - Mock Database Service with Delay Support

@MainActor
final class DelayedMockDatabaseService: DatabaseServiceProtocol {
    var isConnected: Bool = true
    var connectedDatabase: String? = "test"

    /// Delay before returning query results (for race condition testing)
    var queryDelay: TimeInterval = 0

    /// Results to return from executeQuery
    var queryResults: ([TableRow], [String]) = ([], [])

    /// Optional custom query handler for table-specific delay/result behavior in tests
    var queryHandler: ((String) async throws -> ([TableRow], [String]))?

    private(set) var executeQueryCallCount: Int = 0
    private(set) var executeDisplayQueryCallCount: Int = 0
    private(set) var lastExecuteQuerySQL: String?
    private(set) var lastExecuteDisplayQuerySQL: String?
    private(set) var interruptInFlightTableBrowseLoadCallCount: Int = 0

    func connect(host: String, port: Int, username: String, password: String, database: String, sslMode: SSLMode) async throws {
        isConnected = true
        connectedDatabase = database
    }

    func disconnect() async {
        isConnected = false
        connectedDatabase = nil
    }

    func shutdown() async {
        isConnected = false
        connectedDatabase = nil
    }

    func interruptInFlightTableBrowseLoadForSupersession() async {
        interruptInFlightTableBrowseLoadCallCount += 1
    }

    func fetchDatabases() async throws -> [DatabaseInfo] { [] }
    func createDatabase(name: String) async throws {}
    func deleteDatabase(name: String) async throws {}
    func fetchTables(database: String) async throws -> [TableInfo] { [] }
    func fetchSchemas(database: String) async throws -> [String] { [] }
    func deleteTable(schema: String, table: String) async throws {}
    func truncateTable(schema: String, table: String) async throws {}
    func generateDDL(schema: String, table: String) async throws -> String { "" }
    func fetchAllTableData(schema: String, table: String) async throws -> ([TableRow], [String]) { ([], []) }

    private func performQuery(_ sql: String) async throws -> ([TableRow], [String]) {
        if let queryHandler {
            return try await queryHandler(sql)
        }
        if queryDelay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(queryDelay * 1_000_000_000))
        }
        return queryResults
    }

    func executeQuery(_ sql: String) async throws -> ([TableRow], [String]) {
        executeQueryCallCount += 1
        lastExecuteQuerySQL = sql
        return try await performQuery(sql)
    }

    func executeDisplayQuery(_ sql: String) async throws -> ([TableRow], [String]) {
        executeDisplayQueryCallCount += 1
        lastExecuteDisplayQuerySQL = sql
        return try await performQuery(sql)
    }

    func deleteRows(schema: String, table: String, primaryKeyColumns: [String], rows: [TableRow]) async throws {}
    func updateRow(schema: String, table: String, primaryKeyColumns: [String], originalRow: TableRow, updatedValues: [String: RowEditValue]) async throws {}
    func fetchPrimaryKeyColumns(schema: String, table: String) async throws -> [String] { [] }
    func fetchColumnInfo(schema: String, table: String) async throws -> [ColumnInfo] { [] }
}

@MainActor
final class DelayedMockTableMetadataService: TableMetadataServiceProtocol {
    var delayNanoseconds: UInt64 = 0
    private(set) var callCount: Int = 0
    private(set) var cancellationCount: Int = 0
    private(set) var requestedTableIds: [String] = []

    func fetchAndCacheMetadata(
        for table: TableInfo,
        connectionState: ConnectionState,
        databaseService: DatabaseServiceProtocol
    ) async -> (primaryKeys: [String]?, columnInfo: [ColumnInfo]?)? {
        callCount += 1
        requestedTableIds.append(table.id)

        if delayNanoseconds > 0 {
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            } catch {
                cancellationCount += 1
                return nil
            }
        }

        if Task.isCancelled {
            cancellationCount += 1
        }
        return nil
    }

    func updateSelectedTableMetadata(
        connectionState: ConnectionState,
        primaryKeys: [String]?,
        columnInfo: [ColumnInfo]?
    ) {}
}

// MARK: - Test Helpers

@MainActor
private func createTestContext(
    tableMetadataService: TableMetadataServiceProtocol? = nil
) -> (DelayedMockDatabaseService, ConnectionState, QueryState, AppState) {
    let mockService = DelayedMockDatabaseService()
    let connectionState = ConnectionState(databaseService: mockService)
    let queryState = QueryState()
    let appState = AppState(
        connection: connectionState,
        query: queryState,
        tableMetadataService: tableMetadataService
    )
    return (mockService, connectionState, queryState, appState)
}

@MainActor
private func createConnection(name: String) -> ConnectionProfile {
    ConnectionProfile(
        name: name,
        host: "localhost",
        port: 5432,
        username: "test",
        database: "test"
    )
}

// MARK: - AppState Tests

@Suite("AppState")
struct AppStateTests {

    // MARK: - Race Condition Tests

    @Suite("Query Race Conditions")
    @MainActor
    struct QueryRaceConditionTests {

        /// Tests that when rapidly switching tables, a superseded query does NOT
        /// overwrite the current query's results with an error.
        @Test func supersededQueryDoesNotSetError() async {
            let (mockService, connectionState, queryState, appState) = createTestContext()
            mockService.queryResults = ([TableRow(values: ["id": "1"])], ["id"])

            // Set up context
            let connection = createConnection(name: "Test")
            let database = DatabaseInfo(name: "testdb")
            connectionState.currentConnection = connection
            connectionState.selectedDatabase = database

            let table1 = TableInfo(name: "slow_table", schema: "public")
            let table2 = TableInfo(name: "fast_table", schema: "public")
            connectionState.selectedTable = table1

            // Start query for table1 with delay
            mockService.queryDelay = 0.1
            let task1 = Task {
                await appState.executeTableQuery(for: table1)
            }

            // Switch to table2 before query completes
            try? await Task.sleep(nanoseconds: 20_000_000)
            connectionState.selectedTable = table2

            // Execute query for table2 (no delay)
            mockService.queryDelay = 0
            await appState.executeTableQuery(for: table2)

            #expect(queryState.queryError == nil, "Should have no error after table2 query")

            // Wait for table1's delayed query to complete
            await task1.value

            #expect(queryState.queryError == nil, "Superseded query should not set error")
        }

        /// Tests that when a query completes for the currently selected table,
        /// the results ARE applied (baseline test).
        @Test func currentQueryUpdatesState() async {
            let (mockService, connectionState, queryState, appState) = createTestContext()
            let expectedRows = [
                TableRow(values: ["id": "1", "name": "Alice"]),
                TableRow(values: ["id": "2", "name": "Bob"])
            ]
            mockService.queryResults = (expectedRows, ["id", "name"])

            // Set up context
            connectionState.currentConnection = createConnection(name: "Test")
            connectionState.selectedDatabase = DatabaseInfo(name: "testdb")

            let table = TableInfo(name: "users", schema: "public")
            connectionState.selectedTable = table

            await appState.executeTableQuery(for: table)

            #expect(queryState.queryError == nil)
            #expect(queryState.queryResults.count == 2)
            #expect(queryState.queryColumnNames == ["id", "name"])
        }

        /// Tests that clearing table selection mid-query prevents state update.
        @Test func queryIgnoredWhenTableDeselected() async {
            let (mockService, connectionState, queryState, appState) = createTestContext()
            mockService.queryResults = ([TableRow(values: ["id": "1"])], ["id"])
            mockService.queryDelay = 0.05

            // Set up context
            connectionState.currentConnection = createConnection(name: "Test")
            connectionState.selectedDatabase = DatabaseInfo(name: "testdb")

            let table = TableInfo(name: "users", schema: "public")
            connectionState.selectedTable = table

            let task = Task {
                await appState.executeTableQuery(for: table)
            }

            try? await Task.sleep(nanoseconds: 10_000_000)
            connectionState.selectedTable = nil

            await task.value

            #expect(queryState.queryResults.isEmpty, "Results should not be applied when table deselected")
        }

        /// Tests that switching databases mid-query prevents state update,
        /// even when the new database has a table with the same name.
        @Test func queryIgnoredWhenDatabaseChanges() async {
            let (mockService, connectionState, queryState, appState) = createTestContext()
            mockService.queryResults = ([TableRow(values: ["id": "old_db_data"])], ["id"])
            mockService.queryDelay = 0.05

            // Set up initial context
            let connection = createConnection(name: "Test")
            let databaseA = DatabaseInfo(name: "database_a")
            let databaseB = DatabaseInfo(name: "database_b")
            connectionState.currentConnection = connection
            connectionState.selectedDatabase = databaseA

            // Same table name in both databases
            let table = TableInfo(name: "users", schema: "public")
            connectionState.selectedTable = table

            // Start query for table in database_a
            let task = Task {
                await appState.executeTableQuery(for: table)
            }

            // Switch to database_b (which also has "public.users")
            try? await Task.sleep(nanoseconds: 10_000_000)
            connectionState.selectedDatabase = databaseB
            // Table stays selected (same name exists in new database)

            await task.value

            // Results should NOT be applied - wrong database
            #expect(queryState.queryResults.isEmpty, "Results from old database should not be applied")
        }

        /// Tests that switching connections mid-query prevents state update,
        /// even when the new connection has a table with the same name.
        @Test func queryIgnoredWhenConnectionChanges() async {
            let (mockService, connectionState, queryState, appState) = createTestContext()
            mockService.queryResults = ([TableRow(values: ["id": "old_conn_data"])], ["id"])
            mockService.queryDelay = 0.05

            // Set up initial context
            let connectionA = createConnection(name: "Server A")
            let connectionB = createConnection(name: "Server B")
            let database = DatabaseInfo(name: "mydb")
            connectionState.currentConnection = connectionA
            connectionState.selectedDatabase = database

            // Same table name on both servers
            let table = TableInfo(name: "users", schema: "public")
            connectionState.selectedTable = table

            // Start query on connection A
            let task = Task {
                await appState.executeTableQuery(for: table)
            }

            // Switch to connection B (which also has "mydb.public.users")
            try? await Task.sleep(nanoseconds: 10_000_000)
            connectionState.currentConnection = connectionB
            // Database and table stay selected (same names exist)

            await task.value

            // Results should NOT be applied - wrong connection
            #expect(queryState.queryResults.isEmpty, "Results from old connection should not be applied")
        }

        /// Tests the full context change scenario: connection, database, AND table
        /// all have the same identifiers but are different servers.
        @Test func queryIgnoredWhenFullContextChanges() async {
            let (mockService, connectionState, queryState, appState) = createTestContext()
            mockService.queryResults = ([TableRow(values: ["source": "server_a"])], ["source"])
            mockService.queryDelay = 0.05

            // Set up context for Server A
            let connectionA = createConnection(name: "Server A")
            connectionState.currentConnection = connectionA
            connectionState.selectedDatabase = DatabaseInfo(name: "production")
            let table = TableInfo(name: "users", schema: "public")
            connectionState.selectedTable = table

            // Start query on Server A
            let task = Task {
                await appState.executeTableQuery(for: table)
            }

            // Completely switch context to Server B with identical names
            try? await Task.sleep(nanoseconds: 10_000_000)
            let connectionB = createConnection(name: "Server B")
            connectionState.currentConnection = connectionB
            connectionState.selectedDatabase = DatabaseInfo(name: "production")  // Same name!
            connectionState.selectedTable = TableInfo(name: "users", schema: "public")  // Same name!

            await task.value

            // Results should NOT be applied - different connection ID
            #expect(queryState.queryResults.isEmpty, "Results from Server A should not appear on Server B")
        }

        @Test func requestTableQuery_setsTableLoadingImmediately() async {
            let (mockService, connectionState, queryState, appState) = createTestContext()
            mockService.queryResults = ([TableRow(values: ["id": "1"])], ["id"])
            mockService.queryDelay = 0.1

            connectionState.currentConnection = createConnection(name: "Test")
            connectionState.selectedDatabase = DatabaseInfo(name: "testdb")

            let table = TableInfo(name: "users", schema: "public")
            appState.requestTableQuery(for: table)

            #expect(queryState.isExecutingTableQuery == true)
            #expect(queryState.executingTableQueryTableId == table.id)
        }

        @Test func rapidTableClicks_latestWins() async {
            let (mockService, connectionState, queryState, appState) = createTestContext()

            connectionState.currentConnection = createConnection(name: "Test")
            connectionState.selectedDatabase = DatabaseInfo(name: "testdb")

            let slowTable = TableInfo(name: "slow_table", schema: "public")
            let fastTable = TableInfo(name: "fast_table", schema: "public")

            mockService.queryHandler = { sql in
                if sql.contains("\"public\".\"slow_table\"") {
                    try? await Task.sleep(nanoseconds: 120_000_000)
                    return ([TableRow(values: ["source": "slow"])], ["source"])
                }
                if sql.contains("\"public\".\"fast_table\"") {
                    return ([TableRow(values: ["source": "fast"])], ["source"])
                }
                return ([], [])
            }

            appState.requestTableQuery(for: slowTable)
            try? await Task.sleep(nanoseconds: 10_000_000)
            appState.requestTableQuery(for: fastTable)

            try? await Task.sleep(nanoseconds: 220_000_000)

            #expect(connectionState.selectedTable?.id == fastTable.id)
            #expect(queryState.queryResults.count == 1)
            #expect((queryState.queryResults.first?.values["source"] ?? nil) == "fast")
            #expect(queryState.cachedResultsTableId == fastTable.id)
            #expect(queryState.isExecutingTableQuery == false)
            #expect(queryState.executingTableQueryTableId == nil)
        }

        @Test func requestTableQuery_supersedingLoad_invokesHardInterrupt() async {
            let (mockService, connectionState, _, appState) = createTestContext()

            connectionState.currentConnection = createConnection(name: "Test")
            connectionState.selectedDatabase = DatabaseInfo(name: "testdb")

            let firstTable = TableInfo(name: "first_table", schema: "public")
            let secondTable = TableInfo(name: "second_table", schema: "public")

            mockService.queryHandler = { sql in
                if sql.contains("\"public\".\"first_table\"") {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    return ([TableRow(values: ["source": "first"])], ["source"])
                }
                if sql.contains("\"public\".\"second_table\"") {
                    return ([TableRow(values: ["source": "second"])], ["source"])
                }
                return ([], [])
            }

            appState.requestTableQuery(for: firstTable)
            try? await Task.sleep(nanoseconds: 160_000_000) // First request passed debounce and started work
            appState.requestTableQuery(for: secondTable)

            try? await Task.sleep(nanoseconds: 20_000_000)
            #expect(mockService.interruptInFlightTableBrowseLoadCallCount >= 1)
        }

        @Test func rapidTableClicks_latestWins_afterHardInterrupt() async {
            let (mockService, connectionState, queryState, appState) = createTestContext()

            connectionState.currentConnection = createConnection(name: "Test")
            connectionState.selectedDatabase = DatabaseInfo(name: "testdb")

            let slowTable = TableInfo(name: "slow_table", schema: "public")
            let middleTable = TableInfo(name: "middle_table", schema: "public")
            let latestTable = TableInfo(name: "latest_table", schema: "public")

            mockService.queryHandler = { sql in
                if sql.contains("\"public\".\"slow_table\"") {
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    return ([TableRow(values: ["source": "slow"])], ["source"])
                }
                if sql.contains("\"public\".\"middle_table\"") {
                    try? await Task.sleep(nanoseconds: 60_000_000)
                    return ([TableRow(values: ["source": "middle"])], ["source"])
                }
                if sql.contains("\"public\".\"latest_table\"") {
                    return ([TableRow(values: ["source": "latest"])], ["source"])
                }
                return ([], [])
            }

            appState.requestTableQuery(for: slowTable)
            try? await Task.sleep(nanoseconds: 170_000_000)
            appState.requestTableQuery(for: middleTable)
            try? await Task.sleep(nanoseconds: 20_000_000)
            appState.requestTableQuery(for: latestTable)

            try? await Task.sleep(nanoseconds: 420_000_000)

            #expect(mockService.interruptInFlightTableBrowseLoadCallCount >= 1)
            #expect(connectionState.selectedTable?.id == latestTable.id)
            #expect((queryState.queryResults.first?.values["source"] ?? nil) == "latest")
        }

        @Test func executeTableQuery_nonSidebarPath_doesNotInvokeHardInterrupt() async {
            let (mockService, connectionState, queryState, appState) = createTestContext()

            connectionState.currentConnection = createConnection(name: "Test")
            connectionState.selectedDatabase = DatabaseInfo(name: "testdb")

            let firstTable = TableInfo(name: "first_table", schema: "public")
            let secondTable = TableInfo(name: "second_table", schema: "public")

            mockService.queryHandler = { sql in
                if sql.contains("\"public\".\"first_table\"") {
                    try? await Task.sleep(nanoseconds: 180_000_000)
                    return ([TableRow(values: ["source": "first"])], ["source"])
                }
                if sql.contains("\"public\".\"second_table\"") {
                    return ([TableRow(values: ["source": "second"])], ["source"])
                }
                return ([], [])
            }

            let firstTask = Task {
                await appState.executeTableQuery(for: firstTable)
            }

            try? await Task.sleep(nanoseconds: 20_000_000)
            await appState.executeTableQuery(for: secondTable)
            await firstTask.value

            #expect(mockService.interruptInFlightTableBrowseLoadCallCount == 0)
            #expect((queryState.queryResults.first?.values["source"] ?? nil) == "second")
        }

        @Test func tableBrowseRequest_appliesValueCompaction() async {
            let (mockService, connectionState, queryState, appState) = createTestContext()

            connectionState.currentConnection = createConnection(name: "Test")
            connectionState.selectedDatabase = DatabaseInfo(name: "testdb")

            let table = TableInfo(name: "events", schema: "public")
            let longValue = String(repeating: "x", count: Constants.tableBrowseMaxCellCharacters + 256)
            mockService.queryResults = ([TableRow(values: ["payload": longValue])], ["payload"])

            appState.requestTableQuery(for: table, limit: 1)
            try? await Task.sleep(nanoseconds: 320_000_000)

            let compactedValue = queryState.queryResults.first?.values["payload"] ?? nil
            #expect(compactedValue?.hasSuffix(Constants.tableBrowseTruncationSuffix) == true)
            #expect(compactedValue?.count == Constants.tableBrowseMaxCellCharacters)
        }

        @Test func manualExecuteTableQuery_preservesFullValues() async {
            let (mockService, connectionState, queryState, appState) = createTestContext()

            connectionState.currentConnection = createConnection(name: "Test")
            connectionState.selectedDatabase = DatabaseInfo(name: "testdb")

            let table = TableInfo(name: "events", schema: "public")
            let longValue = String(repeating: "y", count: Constants.tableBrowseMaxCellCharacters + 256)
            mockService.queryResults = ([TableRow(values: ["payload": longValue])], ["payload"])

            await appState.executeTableQuery(for: table, limit: 1)

            let value = queryState.queryResults.first?.values["payload"] ?? nil
            #expect(value == longValue)
            #expect(value?.hasSuffix(Constants.tableBrowseTruncationSuffix) == false)
        }

        @Test func requestPaginatedTableQuery_cacheHit_skipsDbAndAppliesImmediately() async {
            let (mockService, connectionState, queryState, appState) = createTestContext()

            let connection = createConnection(name: "Test")
            let database = DatabaseInfo(name: "testdb")
            let table = TableInfo(name: "users", schema: "public")
            connectionState.currentConnection = connection
            connectionState.selectedDatabase = database
            connectionState.selectedTable = table

            let cacheContext = TableBrowsePageCacheContext(
                connectionId: connection.id,
                databaseId: database.id,
                tableId: table.id,
                rowsPerPage: queryState.rowsPerPage
            )
            queryState.cacheTableBrowsePage(
                page: 1,
                rows: [TableRow(values: ["source": "cached_page_1"])],
                columnNames: ["source"],
                hasNextPage: true,
                context: cacheContext
            )

            appState.requestPaginatedTableQuery(for: table, targetPage: 1)

            #expect(mockService.executeQueryCallCount == 0)
            #expect(mockService.executeDisplayQueryCallCount == 0)
            #expect(queryState.currentPage == 1)
            #expect(queryState.hasNextPage == true)
            #expect((queryState.queryResults.first?.values["source"] ?? nil) == "cached_page_1")
            #expect(queryState.isExecutingTableQuery == false)
        }

        @Test func requestPaginatedTableQuery_cacheMiss_appliesCompaction() async {
            let (mockService, connectionState, queryState, appState) = createTestContext()

            connectionState.currentConnection = createConnection(name: "Test")
            connectionState.selectedDatabase = DatabaseInfo(name: "testdb")
            let table = TableInfo(name: "events", schema: "public")
            connectionState.selectedTable = table

            let longValue = String(repeating: "p", count: Constants.tableBrowseMaxCellCharacters + 400)
            mockService.queryResults = ([TableRow(values: ["payload": longValue])], ["payload"])

            appState.requestPaginatedTableQuery(for: table, targetPage: 1)
            try? await Task.sleep(nanoseconds: 220_000_000)

            let compactedValue = queryState.queryResults.first?.values["payload"] ?? nil
            #expect(mockService.executeQueryCallCount == 1)
            #expect(compactedValue?.hasSuffix(Constants.tableBrowseTruncationSuffix) == true)
            #expect(compactedValue?.count == Constants.tableBrowseMaxCellCharacters)
            #expect(queryState.currentPage == 1)
        }

        @Test func rapidPaginationRequests_latestWins_invokesHardInterrupt() async {
            let (mockService, connectionState, queryState, appState) = createTestContext()

            connectionState.currentConnection = createConnection(name: "Test")
            connectionState.selectedDatabase = DatabaseInfo(name: "testdb")
            let table = TableInfo(name: "users", schema: "public")
            connectionState.selectedTable = table
            queryState.currentPage = 0
            queryState.hasNextPage = true

            mockService.queryHandler = { sql in
                if sql.contains("OFFSET 100") {
                    try? await Task.sleep(nanoseconds: 260_000_000)
                    return ([TableRow(values: ["source": "page_1"])], ["source"])
                }
                if sql.contains("OFFSET 200") {
                    return ([TableRow(values: ["source": "page_2"])], ["source"])
                }
                return ([], [])
            }

            appState.requestPaginatedTableQuery(for: table, targetPage: 1)
            try? await Task.sleep(nanoseconds: 30_000_000)
            appState.requestPaginatedTableQuery(for: table, targetPage: 2)

            try? await Task.sleep(nanoseconds: 360_000_000)

            #expect(mockService.interruptInFlightTableBrowseLoadCallCount >= 1)
            #expect(queryState.currentPage == 2)
            #expect((queryState.queryResults.first?.values["source"] ?? nil) == "page_2")
        }

        @Test func paginationFailure_doesNotCommitTargetPage() async {
            let (mockService, connectionState, queryState, appState) = createTestContext()

            connectionState.currentConnection = createConnection(name: "Test")
            connectionState.selectedDatabase = DatabaseInfo(name: "testdb")
            let table = TableInfo(name: "users", schema: "public")
            connectionState.selectedTable = table
            queryState.currentPage = 0
            queryState.hasNextPage = true

            mockService.queryHandler = { sql in
                if sql.contains("OFFSET 100") {
                    throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "page load failed"])
                }
                return ([TableRow(values: ["source": "ok"])], ["source"])
            }

            appState.requestPaginatedTableQuery(for: table, targetPage: 1)
            try? await Task.sleep(nanoseconds: 180_000_000)

            #expect(queryState.currentPage == 0)
            #expect(queryState.queryError != nil)
        }

        @Test func paginationMetadata_cached_skipsRefetch() async {
            let metadataService = DelayedMockTableMetadataService()
            let (mockService, connectionState, queryState, appState) = createTestContext(
                tableMetadataService: metadataService
            )

            connectionState.currentConnection = createConnection(name: "Test")
            connectionState.selectedDatabase = DatabaseInfo(name: "testdb")
            let table = TableInfo(name: "users", schema: "public")
            connectionState.selectedTable = table
            queryState.currentPage = 0
            queryState.hasNextPage = true
            connectionState.tableMetadataCache[table.id] = (
                primaryKeys: [],
                columns: [ColumnInfo(name: "id", dataType: "integer")]
            )

            mockService.queryResults = ([TableRow(values: ["id": "1"])], ["id"])

            appState.requestPaginatedTableQuery(for: table, targetPage: 1)
            try? await Task.sleep(nanoseconds: 180_000_000)

            #expect(metadataService.callCount == 0)
        }

        @Test func pageCache_evictsToThreePages() async {
            let (mockService, connectionState, queryState, appState) = createTestContext()

            let connection = createConnection(name: "Test")
            let database = DatabaseInfo(name: "testdb")
            let table = TableInfo(name: "users", schema: "public")
            connectionState.currentConnection = connection
            connectionState.selectedDatabase = database
            connectionState.selectedTable = table
            queryState.currentPage = 0
            queryState.hasNextPage = true

            mockService.queryHandler = { sql in
                if sql.contains("OFFSET 0") { return ([TableRow(values: ["page": "0"])], ["page"]) }
                if sql.contains("OFFSET 100") { return ([TableRow(values: ["page": "1"])], ["page"]) }
                if sql.contains("OFFSET 200") { return ([TableRow(values: ["page": "2"])], ["page"]) }
                if sql.contains("OFFSET 300") { return ([TableRow(values: ["page": "3"])], ["page"]) }
                return ([], [])
            }

            appState.requestPaginatedTableQuery(for: table, targetPage: 0)
            try? await Task.sleep(nanoseconds: 120_000_000)
            appState.requestPaginatedTableQuery(for: table, targetPage: 1)
            try? await Task.sleep(nanoseconds: 120_000_000)
            appState.requestPaginatedTableQuery(for: table, targetPage: 2)
            try? await Task.sleep(nanoseconds: 120_000_000)
            appState.requestPaginatedTableQuery(for: table, targetPage: 3)
            try? await Task.sleep(nanoseconds: 160_000_000)

            let context = TableBrowsePageCacheContext(
                connectionId: connection.id,
                databaseId: database.id,
                tableId: table.id,
                rowsPerPage: queryState.rowsPerPage
            )

            #expect(queryState.tableBrowsePageCacheCount == Constants.tableBrowseMaxCachedPages)
            #expect(queryState.cachedTableBrowsePage(for: 0, context: context) == nil)
            #expect(queryState.cachedTableBrowsePage(for: 1, context: context) != nil)
            #expect(queryState.cachedTableBrowsePage(for: 3, context: context) != nil)
        }

        @Test func supersededRequest_doesNotClearLatestLoading() async {
            let (mockService, connectionState, queryState, appState) = createTestContext()

            connectionState.currentConnection = createConnection(name: "Test")
            connectionState.selectedDatabase = DatabaseInfo(name: "testdb")

            let firstTable = TableInfo(name: "first_table", schema: "public")
            let latestTable = TableInfo(name: "latest_table", schema: "public")

            mockService.queryHandler = { sql in
                if sql.contains("\"public\".\"first_table\"") {
                    try? await Task.sleep(nanoseconds: 80_000_000)
                    return ([TableRow(values: ["source": "first"])], ["source"])
                }
                if sql.contains("\"public\".\"latest_table\"") {
                    try? await Task.sleep(nanoseconds: 180_000_000)
                    return ([TableRow(values: ["source": "latest"])], ["source"])
                }
                return ([], [])
            }

            appState.requestTableQuery(for: firstTable)
            try? await Task.sleep(nanoseconds: 160_000_000)
            appState.requestTableQuery(for: latestTable)

            try? await Task.sleep(nanoseconds: 90_000_000)
            #expect(queryState.isExecutingTableQuery == true)
            #expect(queryState.executingTableQueryTableId == latestTable.id)

            try? await Task.sleep(nanoseconds: 280_000_000)
            #expect(queryState.isExecutingTableQuery == false)
            #expect(queryState.executingTableQueryTableId == nil)
            #expect((queryState.queryResults.first?.values["source"] ?? nil) == "latest")
        }

        @Test func tableQuery_usesExplicitJsonWrapAndPreservesExpansion() async {
            let (mockService, connectionState, queryState, appState) = createTestContext()

            connectionState.currentConnection = createConnection(name: "Test")
            connectionState.selectedDatabase = DatabaseInfo(name: "testdb")

            let table = TableInfo(name: "users", schema: "public")
            connectionState.selectedTable = table

            mockService.queryHandler = { _ in
                (
                    [TableRow(values: ["row": #"{"id":1,"name":"Alice"}"#])],
                    ["row"]
                )
            }

            await appState.executeTableQuery(for: table, limit: 1)

            #expect(mockService.executeDisplayQueryCallCount == 0)
            #expect(mockService.executeQueryCallCount == 1)
            #expect(mockService.lastExecuteQuerySQL?.contains("SELECT to_jsonb(q) AS row") == true)
            #expect(Set(queryState.queryColumnNames ?? []) == Set(["id", "name"]))
            #expect((queryState.queryResults.first?.values["id"] ?? nil) == "1")
            #expect((queryState.queryResults.first?.values["name"] ?? nil) == "Alice")
        }

        @Test func delayedMetadataFetch_doesNotKeepTableLoadingTrue() async {
            let metadataService = DelayedMockTableMetadataService()
            metadataService.delayNanoseconds = 200_000_000
            let (mockService, connectionState, queryState, appState) = createTestContext(
                tableMetadataService: metadataService
            )

            connectionState.currentConnection = createConnection(name: "Test")
            connectionState.selectedDatabase = DatabaseInfo(name: "testdb")
            let table = TableInfo(name: "users", schema: "public")
            connectionState.selectedTable = table

            mockService.queryResults = ([TableRow(values: ["id": "1"])], ["id"])

            await appState.executeTableQuery(for: table)

            #expect(queryState.isExecutingTableQuery == false)
            #expect(queryState.executingTableQueryTableId == nil)
            #expect(queryState.queryResults.count == 1)

            try? await Task.sleep(nanoseconds: 20_000_000)
            #expect(metadataService.callCount >= 1)
        }

        @Test func rapidTableSwitching_cancelsPreviousMetadataTask_latestWins() async {
            let metadataService = DelayedMockTableMetadataService()
            metadataService.delayNanoseconds = 250_000_000
            let (mockService, connectionState, queryState, appState) = createTestContext(
                tableMetadataService: metadataService
            )

            connectionState.currentConnection = createConnection(name: "Test")
            connectionState.selectedDatabase = DatabaseInfo(name: "testdb")

            let firstTable = TableInfo(name: "first_table", schema: "public")
            let latestTable = TableInfo(name: "latest_table", schema: "public")

            mockService.queryHandler = { sql in
                if sql.contains("\"public\".\"first_table\"") {
                    return ([TableRow(values: ["source": "first"])], ["source"])
                }
                if sql.contains("\"public\".\"latest_table\"") {
                    return ([TableRow(values: ["source": "latest"])], ["source"])
                }
                return ([], [])
            }

            appState.requestTableQuery(for: firstTable)
            try? await Task.sleep(nanoseconds: 180_000_000)
            appState.requestTableQuery(for: latestTable)

            try? await Task.sleep(nanoseconds: 360_000_000)

            #expect((queryState.queryResults.first?.values["source"] ?? nil) == "latest")
            #expect(metadataService.callCount >= 2)
            #expect(metadataService.cancellationCount >= 1)
            #expect(metadataService.requestedTableIds.contains(firstTable.id))
            #expect(metadataService.requestedTableIds.contains(latestTable.id))
        }
    }
}
