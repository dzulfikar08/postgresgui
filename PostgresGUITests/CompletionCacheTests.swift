import Testing
@testable import PostgresGUI

@MainActor
@Suite("CompletionCache Tests")
struct CompletionCacheTests {
    var cache: CompletionCache
    var mockAppState: AppState

    init() {
        // Create a minimal app state for testing
        mockAppState = AppState()

        // Create mock service
        let mockService = MockMetadataService()

        // Use final signature with appState parameter
        cache = CompletionCache(
            metadataService: mockService,
            appState: mockAppState
        )
    }

    @Test("Get tables returns cached metadata")
    func getTablesReturnsCached() async throws {
        // Load metadata
        try await cache.loadMetadata(forDatabase: "testdb")

        // Verify tables are cached
        let cachedTables = cache.getTables(forDatabase: "testdb")
        #expect(cachedTables != nil)
        #expect(cachedTables?.count == 1)
        #expect(cachedTables?.first?.name == "users")
    }

    @Test("Invalidate database clears cache")
    func invalidateDatabaseClearsCache() async throws {
        try await cache.loadMetadata(forDatabase: "testdb")
        #expect(cache.getTables(forDatabase: "testdb") != nil)

        cache.invalidateDatabase("testdb")
        #expect(cache.getTables(forDatabase: "testdb") == nil)
    }

    @Test("Get columns for table returns column info")
    func getColumnsForTable() async throws {
        try await cache.loadMetadata(forDatabase: "testdb")

        let columns = cache.getColumns(forTable: "users", inSchema: "public")
        #expect(columns != nil)
        #expect(columns?.count == 2)
        #expect(columns?.first?.name == "id")
    }
}

// Mock metadata service for testing
@MainActor
class MockMetadataService: MetadataServiceProtocol {
    func fetchDatabases() async throws -> [DatabaseInfo] { return [] }

    func fetchPrimaryKeyColumns(schema: String, table: String) async throws -> [String] {
        return ["id"]
    }

    func fetchColumnInfo(schema: String, table: String) async throws -> [ColumnInfo] {
        return [
            ColumnInfo(name: "id", dataType: "integer"),
            ColumnInfo(name: "username", dataType: "text")
        ]
    }

    func fetchAllSchemaMetadata(databaseId: String) async throws -> [String: [TableInfo]] {
        return [
            "public": [
                TableInfo(
                    name: "users",
                    schema: "public",
                    tableType: .regular,
                    primaryKeyColumns: ["id"],
                    columnInfo: [
                        ColumnInfo(name: "id", dataType: "integer"),
                        ColumnInfo(name: "username", dataType: "text")
                    ]
                )
            ]
        ]
    }
}
