//
//  ConnectionStateTests.swift
//  PostgresGUITests
//
//  Unit tests for ConnectionState metadata cache behavior.
//

import Foundation
import Testing
@testable import PostgresGUI

// MARK: - Mock Database Service

@MainActor
final class MockDatabaseService: DatabaseServiceProtocol {
    var isConnected: Bool = false
    var connectedDatabase: String?
    var metadataService: MetadataServiceProtocol = ConnectionStateMockMetadataService()

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
    }

    func fetchDatabases() async throws -> [DatabaseInfo] {
        return []
    }

    func createDatabase(name: String) async throws {
    }

    func deleteDatabase(name: String) async throws {
    }

    func fetchTables(database: String) async throws -> [TableInfo] {
        return []
    }

    func fetchSchemas(database: String) async throws -> [String] {
        return []
    }

    func deleteTable(schema: String, table: String) async throws {
    }

    func truncateTable(schema: String, table: String) async throws {
    }

    func generateDDL(schema: String, table: String) async throws -> String {
        return ""
    }

    func fetchAllTableData(schema: String, table: String) async throws -> ([TableRow], [String]) {
        return ([], [])
    }

    func executeQuery(_ sql: String) async throws -> ([TableRow], [String]) {
        return ([], [])
    }

    func executeDisplayQuery(_ sql: String) async throws -> ([TableRow], [String]) {
        return ([], [])
    }

    func deleteRows(schema: String, table: String, primaryKeyColumns: [String], rows: [TableRow]) async throws {
    }

    func updateRow(schema: String, table: String, primaryKeyColumns: [String], originalRow: TableRow, updatedValues: [String: RowEditValue]) async throws {
    }

    func fetchPrimaryKeyColumns(schema: String, table: String) async throws -> [String] {
        return []
    }

    func fetchColumnInfo(schema: String, table: String) async throws -> [ColumnInfo] {
        return []
    }

    func fetchAllSchemaMetadata(connection: DatabaseConnectionProtocol) async throws -> [String: [TableInfo]] {
        return [:]
    }
}

@MainActor
class ConnectionStateMockMetadataService: MetadataServiceProtocol {
    func fetchDatabases() async throws -> [DatabaseInfo] { return [] }
    func fetchPrimaryKeyColumns(schema: String, table: String) async throws -> [String] { return [] }
    func fetchColumnInfo(schema: String, table: String) async throws -> [ColumnInfo] { return [] }
    func fetchAllSchemaMetadata(databaseId: String) async throws -> [String: [TableInfo]] { return [:] }
}

// MARK: - ConnectionState Tests

@Suite("ConnectionState")
struct ConnectionStateTests {

    // MARK: - Initialization Tests

    @Suite("Initialization")
    @MainActor
    struct InitializationTests {

        @Test func initialStateHasNoConnection() {
            let mockService = MockDatabaseService()
            let state = ConnectionState(databaseService: mockService)
            #expect(state.currentConnection == nil)
        }

        @Test func initialStateHasNoSelectedDatabase() {
            let mockService = MockDatabaseService()
            let state = ConnectionState(databaseService: mockService)
            #expect(state.selectedDatabase == nil)
        }

        @Test func initialStateHasNoSelectedTable() {
            let mockService = MockDatabaseService()
            let state = ConnectionState(databaseService: mockService)
            #expect(state.selectedTable == nil)
        }

        @Test func initialStateHasEmptyDatabases() {
            let mockService = MockDatabaseService()
            let state = ConnectionState(databaseService: mockService)
            #expect(state.databases.isEmpty)
        }

        @Test func initialStateHasEmptyTables() {
            let mockService = MockDatabaseService()
            let state = ConnectionState(databaseService: mockService)
            #expect(state.tables.isEmpty)
        }

        @Test func initialStateIsNotLoadingTables() {
            let mockService = MockDatabaseService()
            let state = ConnectionState(databaseService: mockService)
            #expect(state.isLoadingTables == false)
        }

        @Test func initialStateHasEmptyMetadataCache() {
            let mockService = MockDatabaseService()
            let state = ConnectionState(databaseService: mockService)
            #expect(state.tableMetadataCache.isEmpty)
        }

        @Test func isConnectedDelegatesToService() {
            let mockService = MockDatabaseService()
            let state = ConnectionState(databaseService: mockService)

            #expect(state.isConnected == false)

            mockService.isConnected = true
            #expect(state.isConnected == true)
        }
    }

    // MARK: - Metadata Cache Tests

    @Suite("Metadata Cache")
    @MainActor
    struct MetadataCacheTests {

        @Test func getPrimaryKeysReturnsCachedValue() {
            let mockService = MockDatabaseService()
            let state = ConnectionState(databaseService: mockService)

            let table = TableInfo(name: "users", schema: "public")
            state.tableMetadataCache["public.users"] = (primaryKeys: ["id", "email"], columns: nil)

            let result = state.getPrimaryKeys(for: table)
            #expect(result == ["id", "email"])
        }

        @Test func getPrimaryKeysReturnsTableValueWhenNotCached() {
            let mockService = MockDatabaseService()
            let state = ConnectionState(databaseService: mockService)

            var table = TableInfo(name: "users", schema: "public")
            table.primaryKeyColumns = ["user_id"]

            let result = state.getPrimaryKeys(for: table)
            #expect(result == ["user_id"])
        }

        @Test func getPrimaryKeysReturnsNilWhenNeitherAvailable() {
            let mockService = MockDatabaseService()
            let state = ConnectionState(databaseService: mockService)

            let table = TableInfo(name: "users", schema: "public")

            let result = state.getPrimaryKeys(for: table)
            #expect(result == nil)
        }

        @Test func getPrimaryKeysPrioritizesCacheOverTable() {
            let mockService = MockDatabaseService()
            let state = ConnectionState(databaseService: mockService)

            var table = TableInfo(name: "users", schema: "public")
            table.primaryKeyColumns = ["table_pk"]
            state.tableMetadataCache["public.users"] = (primaryKeys: ["cached_pk"], columns: nil)

            let result = state.getPrimaryKeys(for: table)
            #expect(result == ["cached_pk"])
        }

        @Test func getColumnInfoReturnsCachedValue() {
            let mockService = MockDatabaseService()
            let state = ConnectionState(databaseService: mockService)

            let table = TableInfo(name: "users", schema: "public")
            let cachedColumns = [
                ColumnInfo(name: "id", dataType: "integer"),
                ColumnInfo(name: "name", dataType: "text")
            ]
            state.tableMetadataCache["public.users"] = (primaryKeys: nil, columns: cachedColumns)

            let result = state.getColumnInfo(for: table)
            #expect(result?.count == 2)
            #expect(result?.first?.name == "id")
        }

        @Test func getColumnInfoReturnsTableValueWhenNotCached() {
            let mockService = MockDatabaseService()
            let state = ConnectionState(databaseService: mockService)

            var table = TableInfo(name: "users", schema: "public")
            table.columnInfo = [ColumnInfo(name: "email", dataType: "text")]

            let result = state.getColumnInfo(for: table)
            #expect(result?.count == 1)
            #expect(result?.first?.name == "email")
        }

        @Test func getColumnInfoReturnsNilWhenNeitherAvailable() {
            let mockService = MockDatabaseService()
            let state = ConnectionState(databaseService: mockService)

            let table = TableInfo(name: "users", schema: "public")

            let result = state.getColumnInfo(for: table)
            #expect(result == nil)
        }
    }

    // MARK: - hasPrimaryKeys Tests

    @Suite("hasPrimaryKeys")
    @MainActor
    struct HasPrimaryKeysTests {

        @Test func returnsTrueWhenCacheHasPrimaryKeys() {
            let mockService = MockDatabaseService()
            let state = ConnectionState(databaseService: mockService)

            let table = TableInfo(name: "users", schema: "public")
            state.tableMetadataCache["public.users"] = (primaryKeys: ["id"], columns: nil)

            #expect(state.hasPrimaryKeys(for: table) == true)
        }

        @Test func returnsTrueWhenTableHasPrimaryKeys() {
            let mockService = MockDatabaseService()
            let state = ConnectionState(databaseService: mockService)

            var table = TableInfo(name: "users", schema: "public")
            table.primaryKeyColumns = ["id"]

            #expect(state.hasPrimaryKeys(for: table) == true)
        }

        @Test func returnsFalseWhenNoPrimaryKeys() {
            let mockService = MockDatabaseService()
            let state = ConnectionState(databaseService: mockService)

            let table = TableInfo(name: "users", schema: "public")

            #expect(state.hasPrimaryKeys(for: table) == false)
        }

        @Test func returnsFalseWhenEmptyPrimaryKeyArray() {
            let mockService = MockDatabaseService()
            let state = ConnectionState(databaseService: mockService)

            let table = TableInfo(name: "users", schema: "public")
            state.tableMetadataCache["public.users"] = (primaryKeys: [], columns: nil)

            #expect(state.hasPrimaryKeys(for: table) == false)
        }

        @Test func returnsTrueForMultiplePrimaryKeys() {
            let mockService = MockDatabaseService()
            let state = ConnectionState(databaseService: mockService)

            let table = TableInfo(name: "order_items", schema: "public")
            state.tableMetadataCache["public.order_items"] = (primaryKeys: ["order_id", "product_id"], columns: nil)

            #expect(state.hasPrimaryKeys(for: table) == true)
        }
    }

    // MARK: - isTableStillSelected Tests

    @Suite("isTableStillSelected")
    @MainActor
    struct IsTableStillSelectedTests {

        @Test func returnsTrueWhenTableIsSelected() {
            let mockService = MockDatabaseService()
            let state = ConnectionState(databaseService: mockService)

            state.selectedTable = TableInfo(name: "users", schema: "public")

            #expect(state.isTableStillSelected("public.users") == true)
        }

        @Test func returnsFalseWhenDifferentTableSelected() {
            let mockService = MockDatabaseService()
            let state = ConnectionState(databaseService: mockService)

            state.selectedTable = TableInfo(name: "orders", schema: "public")

            #expect(state.isTableStillSelected("public.users") == false)
        }

        @Test func returnsFalseWhenNoTableSelected() {
            let mockService = MockDatabaseService()
            let state = ConnectionState(databaseService: mockService)

            state.selectedTable = nil

            #expect(state.isTableStillSelected("public.users") == false)
        }

        @Test func matchesSchemaAndTableName() {
            let mockService = MockDatabaseService()
            let state = ConnectionState(databaseService: mockService)

            state.selectedTable = TableInfo(name: "users", schema: "admin")

            #expect(state.isTableStillSelected("admin.users") == true)
            #expect(state.isTableStillSelected("public.users") == false)
        }
    }

    // MARK: - isQueryContextValid Tests

    @Suite("isQueryContextValid")
    @MainActor
    struct IsQueryContextValidTests {

        @Test func returnsTrueWhenAllMatch() {
            let mockService = MockDatabaseService()
            let state = ConnectionState(databaseService: mockService)

            let connection = ConnectionProfile(
                name: "Test",
                host: "localhost",
                port: 5432,
                username: "user",
                database: "db"
            )
            state.currentConnection = connection
            state.selectedDatabase = DatabaseInfo(name: "mydb")
            state.selectedTable = TableInfo(name: "users", schema: "public")

            let result = state.isQueryContextValid(
                tableId: "public.users",
                databaseId: "mydb",
                connectionId: connection.id
            )
            #expect(result == true)
        }

        @Test func returnsFalseWhenTableDiffers() {
            let mockService = MockDatabaseService()
            let state = ConnectionState(databaseService: mockService)

            let connection = ConnectionProfile(
                name: "Test",
                host: "localhost",
                port: 5432,
                username: "user",
                database: "db"
            )
            state.currentConnection = connection
            state.selectedDatabase = DatabaseInfo(name: "mydb")
            state.selectedTable = TableInfo(name: "orders", schema: "public")

            let result = state.isQueryContextValid(
                tableId: "public.users",  // Different table
                databaseId: "mydb",
                connectionId: connection.id
            )
            #expect(result == false)
        }

        @Test func returnsFalseWhenDatabaseDiffers() {
            let mockService = MockDatabaseService()
            let state = ConnectionState(databaseService: mockService)

            let connection = ConnectionProfile(
                name: "Test",
                host: "localhost",
                port: 5432,
                username: "user",
                database: "db"
            )
            state.currentConnection = connection
            state.selectedDatabase = DatabaseInfo(name: "otherdb")  // Different
            state.selectedTable = TableInfo(name: "users", schema: "public")

            let result = state.isQueryContextValid(
                tableId: "public.users",
                databaseId: "mydb",  // Original database
                connectionId: connection.id
            )
            #expect(result == false)
        }

        @Test func returnsFalseWhenConnectionDiffers() {
            let mockService = MockDatabaseService()
            let state = ConnectionState(databaseService: mockService)

            let connectionA = ConnectionProfile(
                name: "Server A",
                host: "localhost",
                port: 5432,
                username: "user",
                database: "db"
            )
            let connectionB = ConnectionProfile(
                name: "Server B",
                host: "localhost",
                port: 5432,
                username: "user",
                database: "db"
            )
            state.currentConnection = connectionB  // Different connection
            state.selectedDatabase = DatabaseInfo(name: "mydb")
            state.selectedTable = TableInfo(name: "users", schema: "public")

            let result = state.isQueryContextValid(
                tableId: "public.users",
                databaseId: "mydb",
                connectionId: connectionA.id  // Original connection
            )
            #expect(result == false)
        }

        @Test func returnsFalseWhenConnectionIsNil() {
            let mockService = MockDatabaseService()
            let state = ConnectionState(databaseService: mockService)

            state.currentConnection = nil
            state.selectedDatabase = DatabaseInfo(name: "mydb")
            state.selectedTable = TableInfo(name: "users", schema: "public")

            let result = state.isQueryContextValid(
                tableId: "public.users",
                databaseId: "mydb",
                connectionId: UUID()  // Some UUID that won't match nil
            )
            #expect(result == false)
        }

        @Test func returnsTrueWhenBothConnectionIdsAreNil() {
            let mockService = MockDatabaseService()
            let state = ConnectionState(databaseService: mockService)

            state.currentConnection = nil
            state.selectedDatabase = DatabaseInfo(name: "mydb")
            state.selectedTable = TableInfo(name: "users", schema: "public")

            let result = state.isQueryContextValid(
                tableId: "public.users",
                databaseId: "mydb",
                connectionId: nil
            )
            #expect(result == true)
        }
    }

    // MARK: - Cache Key Format Tests

    @Suite("Cache Key Format")
    @MainActor
    struct CacheKeyFormatTests {

        @Test func cacheUsesSchemaQualifiedKey() {
            let mockService = MockDatabaseService()
            let state = ConnectionState(databaseService: mockService)

            // Cache with schema-qualified key
            state.tableMetadataCache["myschema.mytable"] = (primaryKeys: ["id"], columns: nil)

            // Table with matching schema
            let table = TableInfo(name: "mytable", schema: "myschema")

            #expect(state.getPrimaryKeys(for: table) == ["id"])
        }

        @Test func differentSchemasSameName() {
            let mockService = MockDatabaseService()
            let state = ConnectionState(databaseService: mockService)

            state.tableMetadataCache["public.users"] = (primaryKeys: ["public_id"], columns: nil)
            state.tableMetadataCache["admin.users"] = (primaryKeys: ["admin_id"], columns: nil)

            let publicTable = TableInfo(name: "users", schema: "public")
            let adminTable = TableInfo(name: "users", schema: "admin")

            #expect(state.getPrimaryKeys(for: publicTable) == ["public_id"])
            #expect(state.getPrimaryKeys(for: adminTable) == ["admin_id"])
        }
    }
}
