//
//  TableRefreshServiceTests.swift
//  PostgresGUITests
//
//  Unit tests for manual metadata refresh behavior.
//

import Foundation
import Testing
@testable import PostgresGUI

@MainActor
class MockMetadataServiceForTableRefresh: MetadataServiceProtocol {
    func fetchDatabases() async throws -> [DatabaseInfo] { return [] }
    func fetchPrimaryKeyColumns(schema: String, table: String) async throws -> [String] { return [] }
    func fetchColumnInfo(schema: String, table: String) async throws -> [ColumnInfo] { return [] }
    func fetchAllSchemaMetadata(databaseId: String) async throws -> [String: [TableInfo]] { return [:] }
}

@MainActor
final class TableRefreshMockDatabaseService: DatabaseServiceProtocol {
    var isConnected: Bool = true
    var connectedDatabase: String? = "postgres"
    var metadataService: MetadataServiceProtocol = MockMetadataServiceForTableRefresh()

    var databasesToReturn: [DatabaseInfo] = []
    var tablesToReturnByDatabase: [String: [TableInfo]] = [:]
    var schemasToReturnByDatabase: [String: [String]] = [:]
    var queuedTableResponses: [[TableInfo]] = []
    var queuedSchemaResponses: [[String]] = []

    var fetchDatabasesDelayNanoseconds: UInt64 = 0
    var fetchTablesDelayNanoseconds: UInt64 = 0
    var fetchSchemasDelayNanoseconds: UInt64 = 0

    private(set) var fetchDatabasesCallCount: Int = 0
    private(set) var fetchTablesCallCount: Int = 0
    private(set) var fetchSchemasCallCount: Int = 0
    private(set) var fetchTablesDatabases: [String] = []
    private(set) var fetchSchemasDatabases: [String] = []

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

    func interruptInFlightTableBrowseLoadForSupersession() async {}

    func fetchDatabases() async throws -> [DatabaseInfo] {
        fetchDatabasesCallCount += 1
        if fetchDatabasesDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: fetchDatabasesDelayNanoseconds)
        }
        return databasesToReturn
    }

    func createDatabase(name: String) async throws {}

    func deleteDatabase(name: String) async throws {}

    func fetchTables(database: String) async throws -> [TableInfo] {
        fetchTablesCallCount += 1
        fetchTablesDatabases.append(database)
        if fetchTablesDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: fetchTablesDelayNanoseconds)
        }
        if !queuedTableResponses.isEmpty {
            return queuedTableResponses.removeFirst()
        }
        return tablesToReturnByDatabase[database] ?? []
    }

    func fetchSchemas(database: String) async throws -> [String] {
        fetchSchemasCallCount += 1
        fetchSchemasDatabases.append(database)
        if fetchSchemasDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: fetchSchemasDelayNanoseconds)
        }
        if !queuedSchemaResponses.isEmpty {
            return queuedSchemaResponses.removeFirst()
        }
        return schemasToReturnByDatabase[database] ?? []
    }

    func deleteTable(schema: String, table: String) async throws {}

    func truncateTable(schema: String, table: String) async throws {}

    func generateDDL(schema: String, table: String) async throws -> String {
        ""
    }

    func fetchAllTableData(schema: String, table: String) async throws -> ([TableRow], [String]) {
        ([], [])
    }

    func executeQuery(_ sql: String) async throws -> ([TableRow], [String]) {
        ([], [])
    }

    func executeDisplayQuery(_ sql: String) async throws -> ([TableRow], [String]) {
        ([], [])
    }

    func deleteRows(schema: String, table: String, primaryKeyColumns: [String], rows: [TableRow]) async throws {}

    func updateRow(schema: String, table: String, primaryKeyColumns: [String], originalRow: TableRow, updatedValues: [String: RowEditValue]) async throws {}

    func fetchPrimaryKeyColumns(schema: String, table: String) async throws -> [String] {
        []
    }

    func fetchColumnInfo(schema: String, table: String) async throws -> [ColumnInfo] {
        []
    }
}

@Suite("TableRefreshService")
struct TableRefreshServiceTests {
    @MainActor
    private func makeContext() -> (TableRefreshService, TableRefreshMockDatabaseService, ConnectionState, AppState) {
        let databaseService = TableRefreshMockDatabaseService()
        let connectionState = ConnectionState(databaseService: databaseService)
        let appState = AppState(connection: connectionState, query: QueryState())
        let refreshService = TableRefreshService()
        return (refreshService, databaseService, connectionState, appState)
    }

    @MainActor
    private func makeConnection(name: String = "Test") -> ConnectionProfile {
        ConnectionProfile(
            name: name,
            host: "localhost",
            port: 5432,
            username: "postgres",
            database: "postgres"
        )
    }

    @Test
    @MainActor
    func refresh_connected_noSelectedDatabase_refreshesDatabasesOnly() async {
        let (service, databaseService, connectionState, appState) = makeContext()

        connectionState.currentConnection = makeConnection()
        connectionState.selectedDatabase = nil
        databaseService.databasesToReturn = [
            DatabaseInfo(name: "postgres"),
            DatabaseInfo(name: "analytics")
        ]

        await service.refresh(appState: appState)

        #expect(connectionState.databases.map(\.name) == ["postgres", "analytics"])
        #expect(connectionState.databasesVersion == 1)
        #expect(databaseService.fetchDatabasesCallCount == 1)
        #expect(databaseService.fetchTablesCallCount == 0)
        #expect(databaseService.fetchSchemasCallCount == 0)
        #expect(connectionState.isLoadingTables == false)
    }

    @Test
    @MainActor
    func refresh_connected_selectedDatabase_refreshesDatabasesAndTables() async {
        let (service, databaseService, connectionState, appState) = makeContext()

        let selectedDatabase = DatabaseInfo(name: "hikedb")
        connectionState.currentConnection = makeConnection()
        connectionState.selectedDatabase = selectedDatabase
        connectionState.selectedTable = TableInfo(name: "hikes", schema: "public")
        connectionState.selectedSchema = "public"

        databaseService.databasesToReturn = [selectedDatabase, DatabaseInfo(name: "postgres")]
        databaseService.tablesToReturnByDatabase[selectedDatabase.name] = [
            TableInfo(name: "hikes", schema: "public"),
            TableInfo(name: "users", schema: "public")
        ]
        databaseService.schemasToReturnByDatabase[selectedDatabase.name] = ["public", "audit"]

        await service.refresh(appState: appState)

        #expect(databaseService.fetchDatabasesCallCount == 1)
        #expect(databaseService.fetchTablesCallCount == 1)
        #expect(databaseService.fetchSchemasCallCount == 1)
        #expect(databaseService.fetchTablesDatabases == ["hikedb"])
        #expect(databaseService.fetchSchemasDatabases == ["hikedb"])
        #expect(connectionState.tables.map(\.id) == ["public.hikes", "public.users"])
        #expect(connectionState.schemas == ["public", "audit"])
        #expect(connectionState.selectedDatabase?.id == selectedDatabase.id)
        #expect(connectionState.isLoadingTables == false)
    }

    @Test
    @MainActor
    func refresh_selectedDatabaseRemoved_clearsDbAndTableSelection() async {
        let (service, databaseService, connectionState, appState) = makeContext()

        let selectedDatabase = DatabaseInfo(name: "removed_db")
        connectionState.currentConnection = makeConnection()
        connectionState.selectedDatabase = selectedDatabase
        connectionState.selectedTable = TableInfo(name: "events", schema: "public")
        connectionState.selectedSchema = "public"
        connectionState.tables = [TableInfo(name: "events", schema: "public")]
        connectionState.schemas = ["public"]
        connectionState.tableMetadataCache = [
            "public.events": (primaryKeys: ["id"], columns: [ColumnInfo(name: "id", dataType: "uuid")])
        ]

        databaseService.databasesToReturn = [DatabaseInfo(name: "other_db")]

        await service.refresh(appState: appState)

        #expect(connectionState.selectedDatabase == nil)
        #expect(connectionState.selectedTable == nil)
        #expect(connectionState.selectedSchema == nil)
        #expect(connectionState.tables.isEmpty)
        #expect(connectionState.schemas.isEmpty)
        #expect(connectionState.tableMetadataCache.isEmpty)
    }

    @Test
    @MainActor
    func refresh_selectedTableRemoved_clearsSelectedTable() async {
        let (service, databaseService, connectionState, appState) = makeContext()

        let selectedDatabase = DatabaseInfo(name: "hikedb")
        connectionState.currentConnection = makeConnection()
        connectionState.selectedDatabase = selectedDatabase
        connectionState.selectedTable = TableInfo(name: "hikes", schema: "public")

        databaseService.databasesToReturn = [selectedDatabase]
        databaseService.tablesToReturnByDatabase[selectedDatabase.name] = [
            TableInfo(name: "users", schema: "public")
        ]
        databaseService.schemasToReturnByDatabase[selectedDatabase.name] = ["public"]

        await service.refresh(appState: appState)

        #expect(connectionState.selectedTable == nil)
        #expect(connectionState.tables.map(\.id) == ["public.users"])
    }

    @Test
    @MainActor
    func refresh_rapidInvocations_latestWinsOrSingleFlightNoCrash() async {
        let (service, databaseService, connectionState, appState) = makeContext()

        let selectedDatabase = DatabaseInfo(name: "hikedb")
        connectionState.currentConnection = makeConnection()
        connectionState.selectedDatabase = selectedDatabase
        databaseService.databasesToReturn = [selectedDatabase]
        databaseService.fetchDatabasesDelayNanoseconds = 20_000_000
        databaseService.fetchTablesDelayNanoseconds = 80_000_000
        databaseService.queuedTableResponses = [
            [TableInfo(name: "first_pass", schema: "public")],
            [TableInfo(name: "second_pass", schema: "public")]
        ]
        databaseService.queuedSchemaResponses = [
            ["public"],
            ["public"]
        ]

        let first = Task { await service.refresh(appState: appState) }
        try? await Task.sleep(nanoseconds: 10_000_000)
        let second = Task { await service.refresh(appState: appState) }

        await first.value
        await second.value

        #expect(databaseService.fetchDatabasesCallCount == 2)
        #expect(databaseService.fetchTablesCallCount == 2)
        #expect(databaseService.fetchSchemasCallCount == 2)
        #expect(connectionState.tables.first?.name == "second_pass")
        #expect(connectionState.isLoadingTables == false)
    }
}
