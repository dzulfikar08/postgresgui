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

    func fetchDatabases() async throws -> [DatabaseInfo] { [] }
    func createDatabase(name: String) async throws {}
    func deleteDatabase(name: String) async throws {}
    func fetchTables(database: String) async throws -> [TableInfo] { [] }
    func fetchSchemas(database: String) async throws -> [String] { [] }
    func deleteTable(schema: String, table: String) async throws {}
    func truncateTable(schema: String, table: String) async throws {}
    func generateDDL(schema: String, table: String) async throws -> String { "" }
    func fetchAllTableData(schema: String, table: String) async throws -> ([TableRow], [String]) { ([], []) }

    func executeQuery(_ sql: String) async throws -> ([TableRow], [String]) {
        if queryDelay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(queryDelay * 1_000_000_000))
        }
        return queryResults
    }

    func executeDisplayQuery(_ sql: String) async throws -> ([TableRow], [String]) {
        try await executeQuery(sql)
    }

    func deleteRows(schema: String, table: String, primaryKeyColumns: [String], rows: [TableRow]) async throws {}
    func updateRow(schema: String, table: String, primaryKeyColumns: [String], originalRow: TableRow, updatedValues: [String: String?]) async throws {}
    func fetchPrimaryKeyColumns(schema: String, table: String) async throws -> [String] { [] }
    func fetchColumnInfo(schema: String, table: String) async throws -> [ColumnInfo] { [] }
}

// MARK: - Test Helpers

@MainActor
private func createTestContext() -> (DelayedMockDatabaseService, ConnectionState, QueryState, AppState) {
    let mockService = DelayedMockDatabaseService()
    let connectionState = ConnectionState(databaseService: mockService)
    let queryState = QueryState()
    let appState = AppState(
        connection: connectionState,
        query: queryState
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
    }
}
