//
//  DatabaseServiceDeleteDatabaseTests.swift
//  PostgresGUITests
//
//  Unit tests for deleting databases while connected.
//

import Foundation
import Testing
@testable import PostgresGUI

private struct EmptyDatabaseRowSequence: DatabaseRowSequence {
    typealias Element = any DatabaseRow

    struct Iterator: AsyncIteratorProtocol {
        mutating func next() async throws -> (any DatabaseRow)? {
            nil
        }
    }

    func makeAsyncIterator() -> Iterator {
        Iterator()
    }
}

private final class MockDatabaseConnection: DatabaseConnectionProtocol {
    func executeQuery(_ sql: String) async throws -> any DatabaseRowSequence {
        EmptyDatabaseRowSequence()
    }

    func executeQuery(_ sql: String, parameters: [DatabaseParameter]) async throws -> any DatabaseRowSequence {
        EmptyDatabaseRowSequence()
    }
}

private actor DeleteDatabaseMockConnectionManager: ConnectionManagerProtocol {
    private(set) var isConnectedState: Bool = false
    private(set) var currentDatabase: String?
    private var hasStoredCredentials: Bool = false

    private(set) var reconnectRequests: [String] = []
    private(set) var withConnectionCallCount: Int = 0

    private var reconnectFailures: [String: Error] = [:]
    private let mockConnection = MockDatabaseConnection()

    var isConnected: Bool {
        isConnectedState
    }

    func connect(
        host: String,
        port: Int,
        username: String,
        password: String,
        database: String,
        tlsMode: DatabaseTLSMode
    ) async throws {
        isConnectedState = true
        currentDatabase = database
        hasStoredCredentials = true
    }

    func disconnect() async {
        isConnectedState = false
        currentDatabase = nil
    }

    func shutdown() async {
        isConnectedState = false
        currentDatabase = nil
        hasStoredCredentials = false
    }

    func interruptInFlightOperationForSupersession() async {}

    func reconnectUsingStoredCredentials(database: String) async throws {
        guard hasStoredCredentials else {
            throw ConnectionError.notConnected
        }

        reconnectRequests.append(database)

        if let failure = reconnectFailures[database] {
            isConnectedState = false
            currentDatabase = nil
            throw failure
        }

        isConnectedState = true
        currentDatabase = database
    }

    func withConnection<T>(_ operation: @escaping (DatabaseConnectionProtocol) async throws -> T) async throws -> T {
        withConnectionCallCount += 1
        return try await operation(mockConnection)
    }

    func setReconnectFailure(database: String, error: Error) {
        reconnectFailures[database] = error
    }

    static func testConnection(
        host: String,
        port: Int,
        username: String,
        password: String,
        database: String,
        tlsMode: DatabaseTLSMode
    ) async throws -> Bool {
        true
    }
}

private final class DeleteDatabaseMockQueryExecutor: QueryExecutorProtocol {
    private(set) var droppedDatabases: [String] = []

    func fetchDatabases(connection: DatabaseConnectionProtocol) async throws -> [DatabaseInfo] {
        []
    }

    func createDatabase(connection: DatabaseConnectionProtocol, name: String) async throws {}

    func dropDatabase(connection: DatabaseConnectionProtocol, name: String) async throws {
        droppedDatabases.append(name)
    }

    func fetchTables(connection: DatabaseConnectionProtocol) async throws -> [TableInfo] {
        []
    }

    func fetchSchemas(connection: DatabaseConnectionProtocol) async throws -> [String] {
        []
    }

    func fetchTableData(
        connection: DatabaseConnectionProtocol,
        schema: String,
        table: String,
        limit: Int,
        offset: Int
    ) async throws -> [TableRow] {
        []
    }

    func dropTable(connection: DatabaseConnectionProtocol, schema: String, table: String) async throws {}

    func truncateTable(connection: DatabaseConnectionProtocol, schema: String, table: String) async throws {}

    func generateDDL(connection: DatabaseConnectionProtocol, schema: String, table: String) async throws -> String {
        ""
    }

    func fetchColumns(connection: DatabaseConnectionProtocol, schema: String, table: String) async throws -> [ColumnInfo] {
        []
    }

    func fetchPrimaryKeys(connection: DatabaseConnectionProtocol, schema: String, table: String) async throws -> [String] {
        []
    }

    func executeQuery(connection: DatabaseConnectionProtocol, sql: String) async throws -> ([TableRow], [String]) {
        ([], [])
    }

    func updateRow(
        connection: DatabaseConnectionProtocol,
        schema: String,
        table: String,
        primaryKeyColumns: [String],
        originalRow: TableRow,
        updatedValues: [String: RowEditValue]
    ) async throws {}

    func deleteRows(
        connection: DatabaseConnectionProtocol,
        schema: String,
        table: String,
        primaryKeyColumns: [String],
        rows: [TableRow]
    ) async throws {}

    func fetchAllSchemaMetadata(connection: DatabaseConnectionProtocol) async throws -> [String: [TableInfo]] {
        [:]
    }
}

@Suite("DatabaseService.deleteDatabase")
struct DatabaseServiceDeleteDatabaseTests {
    @MainActor
    private func makeConnectedService(database: String) async throws -> (
        service: DatabaseService,
        connectionManager: DeleteDatabaseMockConnectionManager,
        queryExecutor: DeleteDatabaseMockQueryExecutor
    ) {
        let connectionManager = DeleteDatabaseMockConnectionManager()
        let queryExecutor = DeleteDatabaseMockQueryExecutor()
        let service = DatabaseService(
            connectionManager: connectionManager,
            queryExecutor: queryExecutor
        )

        try await service.connect(
            host: "localhost",
            port: 5432,
            username: "postgres",
            password: "",
            database: database,
            sslMode: .default
        )

        return (service, connectionManager, queryExecutor)
    }

    @Test
    @MainActor
    func deleteDatabase_whenTargetIsConnected_switchesToMaintenanceThenDrops() async throws {
        let context = try await makeConnectedService(database: "hikedb")

        try await context.service.deleteDatabase(name: "hikedb")

        #expect(await context.connectionManager.reconnectRequests == ["postgres"])
        #expect(context.queryExecutor.droppedDatabases == ["hikedb"])
        #expect(context.service.connectedDatabase == "postgres")
        #expect(context.service.isConnected)
    }

    @Test
    @MainActor
    func deleteDatabase_whenTargetIsNotConnected_dropsWithoutMaintenanceSwitch() async throws {
        let context = try await makeConnectedService(database: "hikedb")

        try await context.service.deleteDatabase(name: "analytics")

        #expect(await context.connectionManager.reconnectRequests.isEmpty)
        #expect(context.queryExecutor.droppedDatabases == ["analytics"])
        #expect(context.service.connectedDatabase == "hikedb")
        #expect(context.service.isConnected)
    }

    @Test
    @MainActor
    func deleteDatabase_whenDeletingPostgres_usesTemplate1Fallback() async throws {
        let context = try await makeConnectedService(database: "postgres")

        try await context.service.deleteDatabase(name: "postgres")

        #expect(await context.connectionManager.reconnectRequests == ["template1"])
        #expect(context.queryExecutor.droppedDatabases == ["postgres"])
        #expect(context.service.connectedDatabase == "template1")
        #expect(context.service.isConnected)
    }

    @Test
    @MainActor
    func deleteDatabase_whenAllMaintenanceReconnectsFail_throwsAndSkipsDrop() async throws {
        let context = try await makeConnectedService(database: "hikedb")
        await context.connectionManager.setReconnectFailure(
            database: "postgres",
            error: ConnectionError.databaseNotFound("postgres")
        )
        await context.connectionManager.setReconnectFailure(
            database: "template1",
            error: ConnectionError.databaseNotFound("template1")
        )

        do {
            try await context.service.deleteDatabase(name: "hikedb")
            Issue.record("Expected deleteDatabase to throw when all maintenance reconnects fail")
        } catch let connectionError as ConnectionError {
            #expect(connectionError == .databaseNotFound("template1"))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }

        #expect(await context.connectionManager.reconnectRequests == ["postgres", "template1"])
        #expect(context.queryExecutor.droppedDatabases.isEmpty)
        #expect(context.service.connectedDatabase == nil)
        #expect(context.service.isConnected == false)
    }
}
