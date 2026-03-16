import Testing
import AppKit
@testable import PostgresGUI

@MainActor
@Suite("SQLCompletionService Tests")
struct SQLCompletionServiceTests {
    var service: SQLCompletionService
    var mockCache: MockCompletionCache
    var mockAppState: AppState

    init() {
        mockAppState = AppState()
        mockCache = MockCompletionCache()
        let tokenizer = SQLTokenizer()
        service = SQLCompletionService(cache: mockCache, tokenizer: tokenizer)
    }

    @Test("Get completions in FROM clause returns tables")
    func getCompletionsInFromClause() {
        // Setup mock data
        let tables = [
            TableInfo(name: "users", schema: "public", tableType: .regular),
            TableInfo(name: "posts", schema: "public", tableType: .regular)
        ]
        mockCache.setTables(tables, forDatabase: "testdb")

        let suggestions = service.getCompletions(for: "us", inContext: .fromClause)

        #expect(suggestions.contains { $0.text == "users" })
        #expect(!suggestions.contains { $0.text == "posts" })
    }

    @Test("Get completions in SELECT clause returns columns")
    func getCompletionsInSelectClause() {
        // Setup mock columns
        let columns = [
            ColumnInfo(name: "id", dataType: "integer"),
            ColumnInfo(name: "username", dataType: "text")
        ]
        mockCache.setColumns(columns)

        let suggestions = service.getCompletions(for: "use", inContext: .selectClause)

        #expect(suggestions.contains { $0.text == "username" })
    }

    @Test("Detect context works correctly")
    func detectContext() {
        let context = service.detectContext(at: NSRange(location: 9, length: 0), inText: "SELECT id FR")
        #expect(context == .selectClause)
    }

    @Test("Fuzzy matching works with typos")
    func fuzzyMatching() {
        let tables = [
            TableInfo(name: "users", schema: "public", tableType: .regular)
        ]
        mockCache.setTables(tables, forDatabase: "testdb")

        let suggestions = service.getCompletions(for: "usr", inContext: .fromClause)

        // Should match with fuzzy scoring
        #expect(!suggestions.isEmpty)
        #expect(suggestions.allSatisfy { $0.relevanceScore > 0 })
    }
}

// Mock cache for testing - conforms to protocol
@MainActor
class MockCompletionCache: CompletionCacheProtocol {
    private var tables: [TableInfo] = []
    private var columns: [ColumnInfo] = []

    func setTables(_ tables: [TableInfo], forDatabase databaseId: String) {
        self.tables = tables
    }

    func setColumns(_ columns: [ColumnInfo]) {
        self.columns = columns
    }

    func getTables(forDatabase databaseId: String) -> [TableInfo]? {
        return tables.isEmpty ? nil : tables
    }

    func getColumns(forTable tableName: String, inSchema schema: String) -> [ColumnInfo]? {
        return columns.isEmpty ? nil : columns
    }

    func invalidateDatabase(_ databaseId: String) {
        tables = []
        columns = []
    }

    func loadMetadata(forDatabase databaseId: String) async throws {
        // No-op for mock
    }
}
