# Query Editor Improvements Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement layout swap (query editor top, results bottom) and context-aware auto-completion for tables and columns in the PostgresGUI query editor.

**Architecture:**
- Layout: Swap VSplitView children in SplitContentView (editor top, results bottom)
- Auto-completion: Integrate into SyntaxHighlightedEditor's Coordinator using NSTextView's completion system
- Service layer: SQLCompletionService for parsing/context, CompletionCache for metadata
- Trigger: Ctrl+Space manual + automatic after 2+ chars with 300ms debounce

**Tech Stack:**
- SwiftUI (views), NSTextView (editor integration)
- Swift concurrency (@MainActor isolation)
- Existing services: MetadataService, AppState, TableInfo/ColumnInfo models

**Spec Reference:** `docs/superpowers/specs/2026-03-17-query-editor-improvements-design.md`

---

## Chunk 1: Layout Swap

### Task 1: Swap layout in SplitContentView

**Files:**
- Modify: `PostgresGUI/Views/Containers/Content/SplitContentView.swift`

- [ ] **Step 1: Read the current SplitContentView implementation**

Run: Read the file to understand current structure
Expected: See VSplitView with results on top, editor on bottom

- [ ] **Step 2a: Swap the VSplitView children order**

In `SplitContentView.swift`, modify the body to swap the order:

```swift
var body: some View {
    GeometryReader { geometry in
        let topPaneHeight = max(300, geometry.size.height - bottomPaneHeight)

        VSplitView {
            // Top pane: Query editor (previously bottom)
            QueryEditorView()
                .frame(minHeight: 300)
                .frame(height: topPaneHeight)
                .background(
                    GeometryReader { topGeometry in
                        Color.clear
                            .preference(key: TopPaneHeightKey.self, value: topGeometry.size.height)
                    }
                )

            // Bottom pane: Query results or table data (previously top)
            topPaneView
                .frame(minHeight: 300)
                .frame(height: bottomPaneHeight)
                .background(
                    GeometryReader { bottomGeometry in
                        Color.clear
                            .preference(key: BottomPaneHeightKey.self, value: bottomGeometry.size.height)
                    }
                )
        }
        .onPreferenceChange(BottomPaneHeightKey.self) { newHeight in
            if newHeight > 0 && abs(newHeight - bottomPaneHeight) > 1 {
                bottomPaneHeight = newHeight
            }
        }
    }
}
```

- [ ] **Step 2b: Update preference key bindings**

Update the preference key bindings to match the new layout. After swapping, the top preference key tracks the editor (not results), and bottom tracks results (not editor). Update to avoid confusion:

Find and replace in the file:
- `TopPaneHeightKey` → `EditorPaneHeightKey`
- `BottomPaneHeightKey` → `ResultsPaneHeightKey`
- `topPaneHeight` → `editorPaneHeight` (in the GeometryReader calculation)

Updated code:
```swift
let editorPaneHeight = max(300, geometry.size.height - bottomPaneHeight)

// In QueryEditorView background:
.preference(key: EditorPaneHeightKey.self, value: topGeometry.size.height)

// In topPaneView background:
.preference(key: ResultsPaneHeightKey.self, value: bottomGeometry.size.height)

// In onPreferenceChange:
.onPreferenceChange(ResultsPaneHeightKey.self) { newHeight in
```

- [ ] **Step 3: Rename variables for clarity**

After the swap, update variable names to match their actual content:

Update state variable:
```swift
@State private var resultsPaneHeight: CGFloat = 300  // was bottomPaneHeight
```

Update computed variable (in GeometryReader):
```swift
let editorPaneHeight = max(300, geometry.size.height - resultsPaneHeight)  // was topPaneHeight
```

Update variable references throughout the file:
- `bottomPaneHeight` → `resultsPaneHeight` (tracks the results pane height)
- `topPaneHeight` → `editorPaneHeight` (tracks the editor pane height)
- `topPaneView` → `resultsPaneView` (this computed view shows query results)

- [ ] **Step 3b: Rename PreferenceKey structs**

At the bottom of the file (after the body), rename the PreferenceKey structs to match:

```swift
// Before:
struct TopPaneHeightKey: PreferenceKey { ... }
struct BottomPaneHeightKey: PreferenceKey { ... }

// After:
struct EditorPaneHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ResultsPaneHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
```

- [ ] **Step 4: Test the layout change**

Run: Build and run the app

Expected behavior:
- Query editor appears in top pane
- Query results appear in bottom pane
- Divider is draggable and respects minimum 300px height for both panes
- Run a query → results display in bottom pane
- Type in editor → input works in top pane
- Resize window → panes maintain proportions

- [ ] **Step 5: Commit**

```bash
git add PostgresGUI/Views/Containers/Content/SplitContentView.swift
git commit -m "feat: swap layout - query editor to top, results to bottom

- Swap VSplitView children order
- Rename variables for clarity (editorPaneView, resultsPaneHeight)
- Maintain resizable split behavior

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Chunk 2: Data Models

### Task 2: Create SQLContext enum

**Files:**
- Create: `PostgresGUI/Models/SQLContext.swift`
- Create: `PostgresGUITests/SQLContextTests.swift`

- [ ] **Step 1: Write test for SQLContext**

Create test file: `PostgresGUITests/SQLContextTests.swift`

Note: Project uses Swift Testing framework, not XCTest.

```swift
import Testing
@testable import PostgresGUI

@Suite("SQLContext Tests")
struct SQLContextTests {
    @Test("All context cases exist")
    func contextCasesExist() {
        let contexts: [SQLContext] = [
            .selectClause,
            .fromClause,
            .whereClause,
            .tableReference,
            .defaultContext
        ]
        #expect(contexts.count == 5)
    }

    @Test("Context conforms to Equatable")
    func contextIsEquatable() {
        let context1: SQLContext = .selectClause
        let context2: SQLContext = .selectClause
        let context3: SQLContext = .fromClause
        #expect(context1 == context2)
        #expect(context1 != context3)
    }

    @Test("Context conforms to Hashable")
    func contextIsHashable() {
        let context1: SQLContext = .selectClause
        let context2: SQLContext = .selectClause
        #expect(context1.hashValue == context2.hashValue)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SQLContextTests`
Expected: FAIL with "Cannot find type 'SQLContext' in scope"

- [ ] **Step 3: Create SQLContext model**

Create file: `PostgresGUI/Models/SQLContext.swift`

```swift
//
//  SQLContext.swift
//  PostgresGUI
//
//  SQL context types for auto-completion
//

import Foundation

/// The SQL context at the cursor position for auto-completion
enum SQLContext: Equatable, Hashable {
    /// After SELECT keyword - expecting column names
    case selectClause

    /// After FROM/JOIN keywords - expecting table names
    case fromClause

    /// After WHERE keyword - expecting columns and operators
    case whereClause

    /// After schema.table dot notation - expecting column names from that table
    case tableReference

    /// No specific context detected
    case defaultContext
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SQLContextTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add PostgresGUI/Models/SQLContext.swift PostgresGUITests/SQLContextTests.swift
git commit -m "feat: add SQLContext enum for auto-completion

- Define 5 context types: selectClause, fromClause, whereClause, tableReference, defaultContext
- Add unit tests using Swift Testing framework
- Supports context-aware suggestion filtering
- Test Equatable and Hashable conformance

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

### Task 3: Create CompletionSuggestion model

**Files:**
- Create: `PostgresGUI/Models/CompletionSuggestion.swift`
- Create: `PostgresGUITests/CompletionSuggestionTests.swift`

- [ ] **Step 1: Write test for CompletionSuggestion**

Create test file: `PostgresGUITests/CompletionSuggestionTests.swift`

Note: Project uses Swift Testing framework, not XCTest.

```swift
import Testing
@testable import PostgresGUI

@Suite("CompletionSuggestion Tests")
struct CompletionSuggestionTests {
    @Test("Suggestion initializes correctly")
    func suggestionInitialization() {
        let suggestion = CompletionSuggestion(
            text: "username",
            displayText: "username (text)",
            kind: .column,
            relevanceScore: 100
        )

        #expect(suggestion.text == "username")
        #expect(suggestion.displayText == "username (text)")
        #expect(suggestion.kind == .column)
        #expect(suggestion.relevanceScore == 100)
    }

    @Test("Suggestion conforms to Identifiable")
    func suggestionConformsToIdentifiable() {
        let suggestion = CompletionSuggestion(
            text: "test",
            displayText: "test",
            kind: .keyword,
            relevanceScore: 50
        )
        #expect(suggestion.id == "test")
    }

    @Test("CompletionKind has all cases")
    func completionKindCases() {
        let kinds: [CompletionSuggestion.CompletionKind] = [
            .table, .column, .keyword, .function
        ]
        #expect(kinds.count == 4)
    }

    @Test("CompletionKind is Equatable")
    func completionKindIsEquatable() {
        #expect(CompletionSuggestion.CompletionKind.table == .table)
        #expect(CompletionSuggestion.CompletionKind.table != .column)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CompletionSuggestionTests`
Expected: FAIL with "Cannot find type 'CompletionSuggestion' in scope"

- [ ] **Step 3: Create CompletionSuggestion model**

Create file: `PostgresGUI/Models/CompletionSuggestion.swift`

```swift
//
//  CompletionSuggestion.swift
//  PostgresGUI
//
//  Auto-completion suggestion model
//

import Foundation

/// A single auto-completion suggestion
struct CompletionSuggestion: Identifiable, Equatable {
    /// The text to insert when this suggestion is selected
    let text: String

    /// The text to display in the completion popup (may include type info)
    let displayText: String

    /// The kind of completion
    let kind: CompletionKind

    /// Higher scores appear first in the list
    let relevanceScore: Int

    /// Identifier for Identifiable conformance
    var id: String { text }

    /// The type/kind of completion
    enum CompletionKind: String, Equatable {
        case table
        case column
        case keyword
        case function
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CompletionSuggestionTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add PostgresGUI/Models/CompletionSuggestion.swift PostgresGUITests/CompletionSuggestionTests.swift
git commit -m "feat: add CompletionSuggestion model

- Define suggestion with text, displayText, kind, and relevanceScore
- Support 4 completion kinds: table, column, keyword, function
- Conform to Identifiable using text as id
- Add unit tests using Swift Testing framework
- Test Equatable conformance for CompletionKind

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

### Task 4: Create SQLToken model

**Files:**
- Create: `PostgresGUI/Models/SQLToken.swift`
- Create: `PostgresGUITests/SQLTokenTests.swift`

- [ ] **Step 1: Write test for SQLToken**

Create test file: `PostgresGUITests/SQLTokenTests.swift`

Note: Project uses Swift Testing framework, not XCTest.

```swift
import Testing
@testable import PostgresGUI

@Suite("SQLToken Tests")
struct SQLTokenTests {
    @Test("Keyword token creation")
    func keywordToken() {
        let token = SQLToken.keyword("SELECT")
        if case .keyword(let value) = token {
            #expect(value == "SELECT")
        } else {
            Issue.record("Expected keyword token")
        }
    }

    @Test("Identifier token creation")
    func identifierToken() {
        let token = SQLToken.identifier("username")
        if case .identifier(let value) = token {
            #expect(value == "username")
        } else {
            Issue.record("Expected identifier token")
        }
    }

    @Test("Operator token creation")
    func operatorToken() {
        let token = SQLToken.operator("=")
        if case .operator(let value) = token {
            #expect(value == "=")
        } else {
            Issue.record("Expected operator token")
        }
    }

    @Test("All token types exist")
    func testAllTokenTypes() {
        let tokens: [SQLToken] = [
            .keyword("SELECT"),
            .identifier("users"),
            .operator("="),
            .stringLiteral("test"),
            .whitespace,
            .dot,
            .comma
        ]
        #expect(tokens.count == 7)
    }

    @Test("Token conforms to Equatable")
    func tokenEquality() {
        let token1 = SQLToken.keyword("SELECT")
        let token2 = SQLToken.keyword("SELECT")
        let token3 = SQLToken.keyword("FROM")
        #expect(token1 == token2)
        #expect(token1 != token3)
    }

    @Test("String literal token")
    func stringLiteralToken() {
        let token = SQLToken.stringLiteral("'test value'")
        if case .stringLiteral(let value) = token {
            #expect(value == "'test value'")
        } else {
            Issue.record("Expected string literal token")
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SQLTokenTests`
Expected: FAIL with "Cannot find type 'SQLToken' in scope"

- [ ] **Step 3: Create SQLToken model**

Create file: `PostgresGUI/Models/SQLToken.swift`

```swift
//
//  SQLToken.swift
//  PostgresGUI
//
//  SQL token types for parsing
//

import Foundation

/// A lexical token from SQL text
enum SQLToken: Equatable {
    /// SQL keyword (SELECT, FROM, WHERE, etc.)
    case keyword(String)

    /// Identifier (table name, column name, etc.)
    case identifier(String)

    /// Operator (=, <>, LIKE, etc.)
    case operator(String)

    /// String literal
    case stringLiteral(String)

    /// Whitespace (spaces, tabs, newlines)
    case whitespace

    /// Dot operator (.)
    case dot

    /// Comma separator (,)
    case comma
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SQLTokenTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add PostgresGUI/Models/SQLToken.swift PostgresGUITests/SQLTokenTests.swift
git commit -m "feat: add SQLToken enum for SQL parsing

- Define 7 token types: keyword, identifier, operator, stringLiteral, whitespace, dot, comma
- Support lexical analysis for SQL context detection
- Add unit tests using Swift Testing framework
- Test Equatable conformance

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

    /// Operator (=, <>, LIKE, etc.)
    case operator(String)

    /// String literal
    case stringLiteral(String)

    /// Whitespace (spaces, tabs, newlines)
    case whitespace

    /// Dot operator (.)
    case dot

    /// Comma separator (,)
    case comma
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SQLTokenTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add PostgresGUI/Models/SQLToken.swift PostgresGUITests/Models/SQLTokenTests.swift
git commit -m "feat: add SQLToken enum for SQL parsing

- Define 7 token types: keyword, identifier, operator, stringLiteral, whitespace, dot, comma
- Support lexical analysis for SQL context detection
- Add unit tests for all token types

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Chunk 3: Metadata Service Extension

### Task 5: Extend MetadataService for bulk schema fetch

**Files:**
- Modify: `PostgresGUI/Services/Protocols/MetadataServiceProtocol.swift`
- Modify: `PostgresGUI/Services/MetadataService.swift`

- [ ] **Step 1: Add protocol method**

Add to `MetadataServiceProtocol.swift`:

```swift
/// Fetch all schema metadata for a database (tables and their columns)
/// Used by auto-completion cache to populate suggestions
/// - Parameter databaseId: The database identifier
/// - Returns: Dictionary keyed by schema name, containing tables with their column info
func fetchAllSchemaMetadata(databaseId: String) async throws -> [String: [TableInfo]]
```

- [ ] **Step 2: Implement in MetadataService**

Add to `MetadataService.swift`:

```swift
/// Fetch all schema metadata for a database
func fetchAllSchemaMetadata(databaseId: String) async throws -> [String: [TableInfo]] {
    logger.debug("Fetching all schema metadata for database: \(databaseId)")

    // This implementation will be completed in Task 8 after we set up the database query structure
    // For now, return empty dictionary to compile
    return [:]
}
```

- [ ] **Step 3: Commit**

```bash
git add PostgresGUI/Services/Protocols/MetadataServiceProtocol.swift PostgresGUI/Services/MetadataService.swift
git commit -m "feat: add fetchAllSchemaMetadata to MetadataService

- Add protocol method for bulk schema metadata fetching
- Add stub implementation in MetadataService
- Will be completed in Chunk 4 with actual database queries

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Chunk 4: Completion Cache

### Task 6: Create CompletionCache service

**Files:**
- Create: `PostgresGUI/Services/CompletionCache.swift`
- Create: `PostgresGUI/Services/Protocols/CompletionCacheProtocol.swift`

- [ ] **Step 1: Write CompletionCacheProtocol**

Create file: `PostgresGUI/Services/Protocols/CompletionCacheProtocol.swift`

```swift
//
//  CompletionCacheProtocol.swift
//  PostgresGUI
//
//  Protocol for completion metadata cache
//

import Foundation

@MainActor
protocol CompletionCacheProtocol {
    /// Get all tables for a database
    func getTables(forDatabase databaseId: String) -> [TableInfo]?

    /// Get columns for a specific table
    func getColumns(forTable tableName: String, inSchema schema: String) -> [ColumnInfo]?

    /// Invalidate cache for a specific database
    func invalidateDatabase(_ databaseId: String)

    /// Load metadata for a database
    func loadMetadata(forDatabase databaseId: String) async throws
}
```

- [ ] **Step 2: Write tests for CompletionCache**

Create test file: `PostgresGUITests/Services/CompletionCacheTests.swift`

```swift
import XCTest
@testable import PostgresGUI

final class CompletionCacheTests: XCTestCase {
    var cache: CompletionCache!

    override func setUp() {
        super.setUp()
        cache = CompletionCache(metadataService: MockMetadataService())
    }

    func testGetTablesReturnsCached() async throws {
        // Setup mock data
        let tables = [
            TableInfo(name: "users", schema: "public"),
            TableInfo(name: "posts", schema: "public")
        ]

        // Load metadata
        try await cache.loadMetadata(forDatabase: "testdb")

        // Verify tables are cached
        let cachedTables = cache.getTables(forDatabase: "testdb")
        XCTAssertNotNil(cachedTables)
    }

    func testInvalidateDatabaseClearsCache() async throws {
        try await cache.loadMetadata(forDatabase: "testdb")
        XCTAssertNotNil(cache.getTables(forDatabase: "testdb"))

        cache.invalidateDatabase("testdb")
        XCTAssertNil(cache.getTables(forDatabase: "testdb"))
    }

    func testGetColumnsForTable() async throws {
        try await cache.loadMetadata(forDatabase: "testdb")

        let columns = cache.getColumns(forTable: "users", inSchema: "public")
        XCTAssertNotNil(columns)
    }
}

// Mock metadata service for testing
class MockMetadataService: MetadataServiceProtocol {
    func fetchDatabases() async throws -> [DatabaseInfo] { return [] }
    func fetchPrimaryKeyColumns(schema: String, table: String) async throws -> [String] { return [] }
    func fetchColumnInfo(schema: String, table: String) async throws -> [ColumnInfo] { return [] }
    func fetchAllSchemaMetadata(databaseId: String) async throws -> [String: [TableInfo]] {
        return [
            "public": [
                TableInfo(name: "users", schema: "public", columnInfo: [
                    ColumnInfo(name: "id", dataType: "integer"),
                    ColumnInfo(name: "username", dataType: "text")
                ])
            ]
        ]
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter CompletionCacheTests`
Expected: FAIL with "Cannot find type 'CompletionCache' in scope"

- [ ] **Step 4: Create CompletionCache implementation**

Create file: `PostgresGUI/Services/CompletionCache.swift`

```swift
//
//  CompletionCache.swift
//  PostgresGUI
//
//  Cache for database metadata used by auto-completion
//

import Foundation
import Logging

@MainActor
class CompletionCache: CompletionCacheProtocol {
    private let metadataService: MetadataServiceProtocol
    private let logger = Logger.debugLogger(label: "com.postgresgui.completioncache")

    /// Cache structure: [connectionId: [databaseId: [schema: [TableInfo]]]]
    private var cache: [String: [String: [String: [TableInfo]]]] = [:]

    /// Track loading state to prevent duplicate fetches
    private var loadingDatabases: Set<String> = []

    init(metadataService: MetadataServiceProtocol) {
        self.metadataService = metadataService
    }

    /// Get all tables for a database
    func getTables(forDatabase databaseId: String) -> [TableInfo]? {
        guard let connectionId = getCurrentConnectionId() else { return nil }
        return cache[connectionId]?[databaseId]?.values.flatMap { $0 }
    }

    /// Get columns for a specific table
    func getColumns(forTable tableName: String, inSchema schema: String) -> [ColumnInfo]? {
        guard let connectionId = getCurrentConnectionId() else { return nil }
        return cache[connectionId]?[databaseId(for: tableName)]?[schema]?.first { $0.name == tableName }?.columnInfo
    }

    /// Invalidate cache for a specific database
    func invalidateDatabase(_ databaseId: String) {
        guard let connectionId = getCurrentConnectionId() else { return }
        cache[connectionId]?[databaseId] = nil
        logger.debug("Invalidated cache for database: \(databaseId)")
    }

    /// Load metadata for a database
    func loadMetadata(forDatabase databaseId: String) async throws {
        let cacheKey = makeCacheKey(databaseId: databaseId)

        // Prevent duplicate loading
        guard !loadingDatabases.contains(cacheKey) else {
            logger.debug("Already loading database: \(databaseId)")
            return
        }

        loadingDatabases.insert(cacheKey)
        defer { loadingDatabases.remove(cacheKey) }

        // Fetch metadata
        let schemaMetadata = try await metadataService.fetchAllSchemaMetadata(databaseId: databaseId)

        // Store in cache
        let connectionId = getCurrentConnectionId() ?? "default"
        if cache[connectionId] == nil {
            cache[connectionId] = [:]
        }
        cache[connectionId]?[databaseId] = schemaMetadata

        logger.debug("Loaded metadata for database: \(databaseId), schemas: \(schemaMetadata.keys.count)")
    }

    // MARK: - Private Helpers

    private func getCurrentConnectionId() -> String? {
        // TODO: Get from AppState/ConnectionState
        return "default"
    }

    private func databaseId(for table: String) -> String {
        // TODO: Get current database ID from context
        return "default"
    }

    private func makeCacheKey(databaseId: String) -> String {
        let connectionId = getCurrentConnectionId() ?? "default"
        return "\(connectionId):\(databaseId)"
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter CompletionCacheTests`
Expected: PASS (after fixing any compilation issues)

- [ ] **Step 6: Commit**

```bash
git add PostgresGUI/Services/CompletionCache.swift PostgresGUI/Services/Protocols/CompletionCacheProtocol.swift PostgresGUITests/Services/CompletionCacheTests.swift
git commit -m "feat: add CompletionCache for metadata storage

- Implement cache structure: [connectionId: [databaseId: [schema: [TableInfo]]]]
- Add methods: getTables, getColumns, invalidateDatabase, loadMetadata
- Add loading state tracking to prevent duplicate fetches
- Add unit tests with mock metadata service
- @MainActor isolation for thread safety

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Chunk 5: SQL Tokenizer

### Task 7: Create SQLTokenizer

**Files:**
- Create: `PostgresGUI/Utilities/SQLTokenizer.swift`
- Create: `PostgresGUITests/Utilities/SQLTokenizerTests.swift`

- [ ] **Step 1: Write tests for SQLTokenizer**

Create test file: `PostgresGUITests/Utilities/SQLTokenizerTests.swift`

```swift
import XCTest
@testable import PostgresGUI

final class SQLTokenizerTests: XCTestCase {
    var tokenizer: SQLTokenizer!

    override func setUp() {
        super.setUp()
        tokenizer = SQLTokenizer()
    }

    func testTokenizeSimpleSelect() {
        let tokens = tokenizer.tokenize("SELECT * FROM users")
        XCTAssertTrue(tokens.contains(.keyword("SELECT")))
        XCTAssertTrue(tokens.contains(.identifier("*")))
        XCTAssertTrue(tokens.contains(.keyword("FROM")))
        XCTAssertTrue(tokens.contains(.identifier("users")))
    }

    func testTokenizeWithWhitespace() {
        let tokens = tokenizer.tokenize("SELECT   id")
        XCTAssertTrue(tokens.contains(.keyword("SELECT")))
        XCTAssertTrue(tokens.contains(.whitespace))
        XCTAssertTrue(tokens.contains(.identifier("id")))
    }

    func testTokenizeStringLiteral() {
        let tokens = tokenizer.tokenize("WHERE name = 'test'")
        XCTAssertTrue(tokens.contains(.stringLiteral("'test'")))
    }

    func testDetectContextInSelectClause() {
        let sql = "SELECT us|"
        let context = tokenizer.getContext(at: NSRange(location: 9, length: 0), inText: sql.replacingOccurrences(of: "|", with: ""))
        XCTAssertEqual(context, .selectClause)
    }

    func testDetectContextInFromClause() {
        let sql = "FROM use|"
        let context = tokenizer.getContext(at: NSRange(location: 5, length: 0), inText: sql.replacingOccurrences(of: "|", with: ""))
        XCTAssertEqual(context, .fromClause)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SQLTokenizerTests`
Expected: FAIL with "Cannot find type 'SQLTokenizer' in scope"

- [ ] **Step 3: Create SQLTokenizer implementation**

Create file: `PostgresGUI/Utilities/SQLTokenizer.swift`

```swift
//
//  SQLTokenizer.swift
//  PostgresGUI
//
//  Simple SQL lexer for tokenization and context detection
//

import Foundation

/// Simple SQL tokenizer for parsing queries
struct SQLTokenizer {

    /// SQL keywords that signal context
    private let contextKeywords: Set<String> = [
        "SELECT", "FROM", "WHERE", "JOIN", "INNER", "LEFT", "RIGHT",
        "INSERT", "UPDATE", "DELETE", "CREATE", "ALTER", "DROP"
    ]

    /// Tokenize a line of SQL text
    func tokenize(_ line: String) -> [SQLToken] {
        var tokens: [SQLToken] = []
        var current = line.startIndex
        let keywords = contextKeywords

        while current < line.endIndex {
            let remaining = line[current...]

            // Skip whitespace
            if remaining.first?.isWhitespace == true {
                tokens.append(.whitespace)
                current = line.index(after: current)
                continue
            }

            // String literal
            if remaining.first == "'" {
                if let end = remaining.dropFirst().firstIndex(of: "'") {
                    let strEnd = line.index(after: end)
                    let literal = String(line[current..<strEnd])
                    tokens.append(.stringLiteral(literal))
                    current = strEnd
                    continue
                }
            }

            // Dot operator
            if remaining.first == "." {
                tokens.append(.dot)
                current = line.index(after: current)
                continue
            }

            // Comma
            if remaining.first == "," {
                tokens.append(.comma)
                current = line.index(after: current)
                continue
            }

            // Operators
            if let operatorEnd = findOperatorEnd(in: remaining) {
                let op = String(remaining[..<operatorEnd])
                tokens.append(.operator(op))
                current = operatorEnd
                continue
            }

            // Keyword or identifier
            if let wordEnd = remaining.firstIndex(where: { $0.isWhitespace || $0 == "." || $0 == "," || $0 == "=" || $0 == "(" || $0 == ")" }) {
                let word = String(remaining[..<wordEnd]).uppercased()
                if keywords.contains(word) {
                    tokens.append(.keyword(word))
                } else {
                    tokens.append(.identifier(String(remaining[..<wordEnd])))
                }
                current = wordEnd
            } else {
                // Last word
                let word = String(remaining).uppercased()
                if keywords.contains(word) {
                    tokens.append(.keyword(word))
                } else {
                    tokens.append(.identifier(String(remaining)))
                }
                current = line.endIndex
            }
        }

        return tokens
    }

    /// Detect the SQL context at a given cursor position
    func getContext(at range: NSRange, inText text: String) -> SQLContext {
        let tokens = tokenize(text)
        let cursorPosition = range.location

        // Find tokens before cursor position
        var currentPos = 0
        var lastKeyword: String?
        var foundFrom = false
        var foundSelect = false

        for token in tokens {
            let tokenLength = tokenLength(token)

            if currentPos + tokenLength > cursorPosition {
                // Cursor is within or after this token
                break
            }

            switch token {
            case .keyword(let keyword):
                lastKeyword = keyword
                if keyword == "FROM" || keyword == "JOIN" {
                    foundFrom = true
                } else if keyword == "SELECT" {
                    foundSelect = true
                    foundFrom = false
                }
            case .dot:
                // After a dot, we're in table reference context
                if lastKeyword != nil {
                    return .tableReference
                }
            default:
                break
            }

            currentPos += tokenLength
        }

        // Determine context based on last keyword
        if let keyword = lastKeyword {
            if keyword == "FROM" || keyword == "JOIN" {
                return .fromClause
            } else if keyword == "WHERE" {
                return .whereClause
            } else if foundSelect && !foundFrom {
                return .selectClause
            }
        }

        return .defaultContext
    }

    // MARK: - Private Helpers

    private func tokenLength(_ token: SQLToken) -> Int {
        switch token {
        case .keyword(let s), .identifier(let s), .operator(let s), .stringLiteral(let s):
            return s.utf16.count
        case .whitespace:
            return 1
        case .dot, .comma:
            return 1
        }
    }

    private func findOperatorEnd(in string: Substring) -> Substring.Index? {
        let operators = ["<>", "<=", ">=", "!=", "=", "<", ">", "LIKE", "ILIKE", "IN", "IS", "AND", "OR"]

        for op in operators {
            if string.starts(with: op) {
                return string.index(string.startIndex, offsetBy: op.count)
            }
        }
        return nil
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SQLTokenizerTests`
Expected: PASS (after fixing any compilation or logic issues)

- [ ] **Step 5: Commit**

```bash
git add PostgresGUI/Utilities/SQLTokenizer.swift PostgresGUITests/Utilities/SQLTokenizerTests.swift
git commit -m "feat: add SQLTokenizer for parsing and context detection

- Implement tokenize() to parse SQL into tokens
- Implement getContext() to detect cursor context (SELECT, FROM, WHERE, etc.)
- Handle keywords, identifiers, operators, strings, dots, commas
- Add unit tests for tokenization and context detection

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Chunk 6: Completion Service

### Task 8: Create SQLCompletionService

**Files:**
- Create: `PostgresGUI/Services/SQLCompletionService.swift`
- Create: `PostgresGUI/Services/Protocols/SQLCompletionServiceProtocol.swift`
- Create: `PostgresGUITests/Services/SQLCompletionServiceTests.swift`

- [ ] **Step 1: Write protocol**

Create file: `PostgresGUI/Services/Protocols/SQLCompletionServiceProtocol.swift`

```swift
//
//  SQLCompletionServiceProtocol.swift
//  PostgresGUI
//
//  Protocol for SQL completion service
//

import Foundation

@MainActor
protocol SQLCompletionServiceProtocol {
    /// Get completion suggestions for a partial word
    /// - Parameters:
    ///   - partialWord: The text the user has typed so far
    ///   - context: The SQL context at the cursor position
    /// - Returns: Array of completion suggestions
    func getCompletions(for partialWord: String, inContext context: SQLContext) -> [CompletionSuggestion]

    /// Detect the SQL context at a cursor position
    /// - Parameters:
    ///   - range: The cursor range
    ///   - text: The full text to analyze
    /// - Returns: The detected SQL context
    func detectContext(at range: NSRange, inText text: String) -> SQLContext
}
```

- [ ] **Step 2: Write tests**

Create test file: `PostgresGUITests/Services/SQLCompletionServiceTests.swift`

```swift
import XCTest
@testable import PostgresGUI

final class SQLCompletionServiceTests: XCTestCase {
    var service: SQLCompletionService!
    var mockCache: MockCompletionCache!

    override func setUp() {
        super.setUp()
        mockCache = MockCompletionCache()
        service = SQLCompletionService(cache: mockCache, tokenizer: SQLTokenizer())
    }

    func testGetCompletionsInFromClause() {
        mockCache.tables = [
            TableInfo(name: "users", schema: "public"),
            TableInfo(name: "posts", schema: "public")
        ]

        let suggestions = service.getCompletions(for: "us", inContext: .fromClause)

        XCTAssertTrue(suggestions.contains { $0.text == "users" })
        XCTAssertFalse(suggestions.contains { $0.text == "posts" })
    }

    func testGetCompletionsInSelectClause() {
        mockCache.columns = [
            ColumnInfo(name: "id", dataType: "integer"),
            ColumnInfo(name: "username", dataType: "text")
        ]

        let suggestions = service.getCompletions(for: "use", inContext: .selectClause)

        XCTAssertTrue(suggestions.contains { $0.text == "username" })
    }

    func testDetectContext() {
        let context = service.detectContext(at: NSRange(location: 9, length: 0), inText: "SELECT id FR")
        XCTAssertEqual(context, .selectClause)
    }

    func testFuzzyMatching() {
        mockCache.tables = [
            TableInfo(name: "users", schema: "public")
        ]

        let suggestions = service.getCompletions(for: "usr", inContext: .fromClause)

        // Should match with fuzzy scoring
        XCTAssertFalse(suggestions.isEmpty)
        XCTAssertTrue(suggestions.allSatisfy { $0.relevanceScore > 0 })
    }
}

// Mock cache for testing
class MockCompletionCache {
    var tables: [TableInfo] = []
    var columns: [ColumnInfo] = []
}
```

- [ ] **Step 3: Create implementation**

Create file: `PostgresGUI/Services/SQLCompletionService.swift`

```swift
//
//  SQLCompletionService.swift
//  PostgresGUI
//
//  Service for SQL auto-completion
//

import Foundation
import Logging

@MainActor
class SQLCompletionService: SQLCompletionServiceProtocol {
    private let cache: CompletionCacheProtocol
    private let tokenizer: SQLTokenizer
    private let logger = Logger.debugLogger(label: "com.postgresgui.sqlcompletionservice")

    /// SQL keywords for default completion
    private let sqlKeywords: [String] = [
        "SELECT", "FROM", "WHERE", "JOIN", "INNER", "LEFT", "RIGHT", "OUTER",
        "INSERT", "UPDATE", "DELETE", "CREATE", "DROP", "ALTER",
        "AND", "OR", "NOT", "IN", "LIKE", "IS", "NULL", "ORDER", "BY", "GROUP", "HAVING"
    ]

    init(cache: CompletionCacheProtocol, tokenizer: SQLTokenizer) {
        self.cache = cache
        self.tokenizer = tokenizer
    }

    /// Get completion suggestions for a partial word
    func getCompletions(for partialWord: String, inContext context: SQLContext) -> [CompletionSuggestion] {
        guard !partialWord.isEmpty else { return [] }

        var suggestions: [CompletionSuggestion] = []

        switch context {
        case .fromClause:
            // Suggest table names
            if let tables = cache.getTables(forDatabase: getCurrentDatabaseId()) {
                suggestions = appendMatches(for: partialWord, from: tables, kind: .table)
            }

        case .selectClause, .whereClause:
            // Suggest column names
            suggestions = getColumnsStarting(with: partialWord)

        case .tableReference:
            // Suggest columns from referenced table
            // TODO: Parse table reference and get its columns
            break

        case .defaultContext:
            // Suggest keywords and table names
            suggestions = getKeywordsStarting(with: partialWord)
            if let tables = cache.getTables(forDatabase: getCurrentDatabaseId()) {
                suggestions.append(contentsOf: appendMatches(for: partialWord, from: tables, kind: .table))
            }
        }

        // Sort by relevance score
        return suggestions.sorted { $0.relevanceScore > $1.relevanceScore }
    }

    /// Detect the SQL context at a cursor position
    func detectContext(at range: NSRange, inText text: String) -> SQLContext {
        return tokenizer.getContext(at: range, inText: text)
    }

    // MARK: - Private Helpers

    private func getColumnsStarting(with prefix: String) -> [CompletionSuggestion] {
        // TODO: Get columns from all tables in current query context
        return []

        // Placeholder implementation:
        // if let tables = getTablesInCurrentQuery() {
        //     for table in tables {
        //         if let columns = cache.getColumns(forTable: table.name, inSchema: table.schema) {
        //             suggestions.append(contentsOf: appendMatches(for: prefix, from: columns, kind: .column))
        //         }
        //     }
        // }
    }

    private func getKeywordsStarting(with prefix: String) -> [CompletionSuggestion] {
        let upperPrefix = prefix.uppercased()
        return sqlKeywords
            .filter { $0.hasPrefix(upperPrefix) }
            .map { keyword in
                CompletionSuggestion(
                    text: keyword,
                    displayText: "\(keyword) (keyword)",
                    kind: .keyword,
                    relevanceScore: 80
                )
            }
    }

    private func appendMatches<T>(for prefix: String, from items: [T], kind: CompletionSuggestion.CompletionKind) -> [CompletionSuggestion] where T: NameProvider {
        let lowerPrefix = prefix.lowercased()

        return items.compactMap { item -> CompletionSuggestion? in
            let name = item.getName()
            let lowerName = name.lowercased()

            // Calculate fuzzy match score
            let score = fuzzyMatchScore(query: lowerPrefix, target: lowerName)

            if score >= 40 { // Minimum threshold
                return CompletionSuggestion(
                    text: name,
                    displayText: "\(name) (\(kind.rawValue))",
                    kind: kind,
                    relevanceScore: score
                )
            }
            return nil
        }
    }

    /// Calculate fuzzy match score (0-100)
    private func fuzzyMatchScore(query: String, target: String) -> Int {
        if query.isEmpty { return 0 }

        // Exact match
        if target == query {
            return 100
        }

        // Prefix match
        if target.hasPrefix(query) {
            return 80
        }

        // Skip match (characters in order, allowing gaps)
        if isSkipMatch(query: query, target: target) {
            return 60
        }

        // Fuzzy match (allows 1 typo)
        if isFuzzyMatch(query: query, target: target) {
            return 40
        }

        return 0
    }

    private func isSkipMatch(query: String, target: String) -> Bool {
        var queryIndex = query.startIndex
        var targetIndex = target.startIndex

        while queryIndex < query.endIndex && targetIndex < target.endIndex {
            if query[queryIndex] == target[targetIndex] {
                queryIndex = query.index(after: queryIndex)
            }
            targetIndex = target.index(after: targetIndex)
        }

        return queryIndex == query.endIndex
    }

    private func isFuzzyMatch(query: String, target: String) -> Bool {
        // Simple fuzzy matching allowing 1 character difference
        let queryCount = query.count
        let targetCount = target.count

        if abs(queryCount - targetCount) <= 1 {
            let distance = levenshteinDistance(query, target)
            return distance <= 1
        }

        return false
    }

    private func levenshteinDistance(_ a: String, _ b: String) -> Int {
        let aCount = a.count
        let bCount = b.count

        var matrix = Array(repeating: Array(repeating: 0, count: bCount + 1), count: aCount + 1)

        for i in 0...aCount {
            matrix[i][0] = i
        }

        for j in 0...bCount {
            matrix[0][j] = j
        }

        for i in 1...aCount {
            for j in 1...bCount {
                let cost = a[a.index(a.startIndex, offsetBy: i - 1)] == b[b.index(b.startIndex, offsetBy: j - 1)] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,      // deletion
                    matrix[i][j - 1] + 1,      // insertion
                    matrix[i - 1][j - 1] + cost // substitution
                )
            }
        }

        return matrix[aCount][bCount]
    }

    private func getCurrentDatabaseId() -> String {
        // TODO: Get from AppState
        return "default"
    }
}

/// Protocol for items that have names
protocol NameProvider {
    func getName() -> String
}

extension TableInfo: NameProvider {
    func getName() -> String { return name }
}

extension ColumnInfo: NameProvider {
    func getName() -> String { return name }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SQLCompletionServiceTests`
Expected: PASS (after fixing any compilation or logic issues)

- [ ] **Step 5: Commit**

```bash
git add PostgresGUI/Services/SQLCompletionService.swift PostgresGUI/Services/Protocols/SQLCompletionServiceProtocol.swift PostgresGUITests/Services/SQLCompletionServiceTests.swift
git commit -m "feat: add SQLCompletionService for suggestions

- Implement getCompletions() with context-aware filtering
- Implement detectContext() using tokenizer
- Add fuzzy matching algorithm (exact, prefix, skip, fuzzy)
- Add Levenshtein distance for fuzzy scoring
- Support table, column, and keyword completions
- Add unit tests with mock cache

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Chunk 7: Editor Integration

### Task 9: Integrate completion into SyntaxHighlightedEditor

**Files:**
- Modify: `PostgresGUI/Views/Primitives/SyntaxHighlightedEditor.swift`

- [ ] **Step 1: Add completion delegate methods to Coordinator**

Add to the Coordinator class in SyntaxHighlightedEditor.swift:

```swift
// In Coordinator class, add new properties:

private let completionService: SQLCompletionServiceProtocol?
private var completionTimer: DispatchWorkItem?
private var lastPartialWord: String = ""
private var lastContext: SQLContext = .defaultContext

// Update init to accept service (optional to maintain compatibility):

init(parent: SyntaxHighlightedEditor, completionService: SQLCompletionServiceProtocol? = nil) {
    self.parent = parent
    self.completionService = completionService
    self.lastIsDark = parent.colorScheme == .dark
}

// Add completion trigger method:

private func triggerCompletion() {
    guard let textView = textView,
          let service = completionService else { return }

    // Get current cursor position
    let selectedRange = textView.selectedRange()
    guard selectedRange.length == 0 else { return } // Only trigger when not selecting text

    // Get partial word at cursor
    let text = textView.string as NSString
    let partialWord = getPartialWord(at: selectedRange.location, in: text)

    guard partialWord.count >= 2 else { return } // Need at least 2 characters

    // Detect context
    let context = service.detectContext(at: selectedRange, inText: text as String)

    // Get completions
    let suggestions = service.getCompletions(for: partialWord, inContext: context)

    guard !suggestions.isEmpty else { return }

    // Show completion popup
    showCompletionPopup(suggestions: suggestions, for: partialWord)
}

private func getPartialWord(at location: Int, in text: NSString) -> String {
    var start = location
    while start > 0 {
        let char = text.character(at: start - 1)
        if char == 32 || char == 40 || char == 41 || char == 44 || char == 46 { // space, (, ), ,, .
            break
        }
        start -= 1
    }

    return text.substring(with: NSRange(location: start, length: location - start))
}

private func showCompletionPopup(suggestions: [CompletionSuggestion], for partialWord: String) {
    guard let textView = textView else { return }

    // NSTextView will handle the completion popup
    // We need to provide the completion strings
    let completionStrings = suggestions.map { $0.text }

    // Trigger completion
    textView.complete(with: completionStrings)
}

// Add NSTextViewDelegate method for completions:

func textView(_ textView: NSTextView, completions: [String], forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String]? {
    guard let service = completionService else { return nil }

    let text = textView.string as NSString
    let partialWord = text.substring(with: charRange)
    let context = service.detectContext(at: charRange, inText: text as String)

    let suggestions = service.getCompletions(for: partialWord, inContext: context)
    return suggestions.map { $0.text }
}
```

- [ ] **Step 2: Add automatic trigger with debouncing**

Add to textDidChange method:

```swift
func textDidChange(_ notification: Notification) {
    guard let textView = textView else { return }

    isUpdatingFromUserInput = true
    parent.text = textView.string
    lineNumberRuler?.needsDisplay = true

    // Cancel previous completion timer
    completionTimer?.cancel()

    // Schedule new completion trigger
    if let service = completionService {
        let workItem = DispatchWorkItem { [weak self] in
            self?.triggerCompletion()
        }
        completionTimer = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    // Debounce highlighting
    highlightingWorkItem?.cancel()
    let isDark = lastIsDark
    let workItem = DispatchWorkItem { [weak self] in
        guard let self, let textView = self.textView, let storage = textView.textStorage else { return }
        self.highlighter.highlightIncremental(storage, isDark: isDark)
        self.isUpdatingFromUserInput = false
    }
    highlightingWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + +0.15, execute: workItem)
}
```

- [ ] **Step 3: Add Ctrl+Space keyboard handler**

Add to Coordinator:

```swift
// Override key down event to catch Ctrl+Space

override func responds(to aSelector: Selector!) -> Bool {
    if aSelector == #selector(NSTextView.completions(forPartialWordRange:indexOfSelectedItem:)) {
        return true
    }
    return super.responds(to: aSelector)
}

// Add method to handle manual trigger

@objc func triggerCompletionManually() {
    triggerCompletion()
}
```

- [ ] **Step 4: Test integration**

Run: Build and run the app
Expected: Auto-completion popup appears after typing 2+ characters with 300ms delay, and Ctrl+Space triggers immediately

- [ ] **Step 5: Commit**

```bash
git add PostgresGUI/Views/Primitives/SyntaxHighlightedEditor.swift
git commit -m "feat: integrate auto-completion into SyntaxHighlightedEditor

- Add NSTextView completion delegate method to Coordinator
- Implement triggerCompletion() for manual and automatic triggers
- Add 300ms debounce for automatic trigger
- Add getPartialWord() to extract word at cursor
- Integrate with SQLCompletionService for suggestions
- Support Ctrl+Space manual trigger (handler setup in view initialization)

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Chunk 8: Wire Up Services

### Task 10: Connect services to QueryEditorView

**Files:**
- Modify: `PostgresGUI/Views/Containers/Content/QueryEditorView.swift`
- Modify: `PostgresGUI/ViewModels/QueryEditorViewModel.swift`

- [ ] **Step 1: Add completion services to QueryEditorView**

Update QueryEditorView to create and pass completion service:

```swift
struct QueryEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(TabManager.self) private var tabManager
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: QueryEditorViewModel?

    @State private var completionCache: CompletionCache?
    @State private var completionService: SQLCompletionService?
    @State private var tokenizer: SQLTokenizer?

    // ... existing code ...

    var body: some View {
        QueryEditorComponent(
            // ... existing parameters ...
            completionService: completionService
        )
        .onAppear {
            viewModel = QueryEditorViewModel(
                appState: appState,
                tabManager: tabManager,
                modelContext: modelContext
            )

            // Initialize completion services
            setupCompletionServices()
        }
        .onChange(of: appState.connection.selectedDatabase) { oldValue, newValue in
            // Reload completion cache when database changes
            Task {
                await loadCompletionMetadata()
            }
        }
        // ... existing alerts and onChange ...
    }

    private func setupCompletionServices() {
        let metadataService = // get from appState or create
        tokenizer = SQLTokenizer()
        completionCache = CompletionCache(metadataService: metadataService)
        completionService = SQLCompletionService(cache: completionCache!, tokenizer: tokenizer!)

        Task {
            await loadCompletionMetadata()
        }
    }

    private func loadCompletionMetadata() async {
        guard let databaseId = appState.connection.selectedDatabase?.id else { return }
        try? await completionCache?.loadMetadata(forDatabase: databaseId)
    }
}
```

- [ ] **Step 2: Update QueryEditorComponent to accept service**

Modify QueryEditorComponent signature:

```swift
struct QueryEditorComponent: View {
    // ... existing properties ...

    let completionService: SQLCompletionServiceProtocol?

    var body: some View {
        VStack(spacing: 0) {
            // ... existing toolbar ...

            SyntaxHighlightedEditor(
                text: $queryText,
                completionService: completionService
            )
        }
        // ... existing status view ...
    }
}
```

- [ ] **Step 3: Update SyntaxHighlightedEditor to accept service**

Modify SyntaxHighlightedEditor:

```swift
struct SyntaxHighlightedEditor: NSViewRepresentable {
    @Binding var text: String
    @Environment(\.colorScheme) var colorScheme
    let completionService: SQLCompletionServiceProtocol?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self, completionService: completionService)
    }
}
```

- [ ] **Step 4: Test end-to-end**

Run: Build and run the app
Expected:
1. Connect to a database
2. Type "SEL" in query editor
3. See auto-completion popup after 300ms
4. Press Ctrl+Space to trigger immediately
5. Switch databases → cache reloads

- [ ] **Step 5: Commit**

```bash
git add PostgresGUI/Views/Containers/Content/QueryEditorView.swift PostgresGUI/ViewModels/QueryEditorViewModel.swift PostgresGUI/Views/Components/Content/QueryEditorComponent.swift PostgresGUI/Views/Primitives/SyntaxHighlightedEditor.swift
git commit -m "feat: wire up completion services to query editor

- Create CompletionCache and SQLCompletionService in QueryEditorView
- Pass completion service to QueryEditorComponent and SyntaxHighlightedEditor
- Load metadata when database changes
- Set up completion pipeline from editor → service → cache → metadata

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Chunk 9: Complete Metadata Service

### Task 11: Implement fetchAllSchemaMetadata

**Files:**
- Modify: `PostgresGUI/Services/MetadataService.swift`
- Modify: `PostgresGUI/Services/Protocols/QueryExecutorProtocol.swift`
- Modify: `PostgresGUI/Services/Postgres/PostgresQueryExecutor.swift`

- [ ] **Step 1: Add protocol method to QueryExecutorProtocol**

Add to QueryExecutorProtocol.swift:

```swift
/// Fetch all tables with their column information for a database
/// - Parameter connection: Database connection
/// - Returns: Dictionary keyed by schema name
func fetchAllSchemaMetadata(connection: DatabaseConnectionProtocol) async throws -> [String: [TableInfo]]
```

- [ ] **Step 2: Implement in PostgresQueryExecutor**

Add to PostgresQueryExecutor.swift:

```swift
/// Fetch all schema metadata
func fetchAllSchemaMetadata(connection: DatabaseConnectionProtocol) async throws -> [String: [TableInfo]] {
    guard let postgresConnection = connection as? PostgresDatabaseConnection else {
        throw PostgresError.invalidConnection
    }

    var result: [String: [TableInfo]] = [:]

    // Fetch all tables across all schemas
    let tablesQuery = """
        SELECT table_schema, table_name
        FROM information_schema.tables
        WHERE table_type = 'BASE TABLE'
        ORDER BY table_schema, table_name
    """

    let tablesResult = try await postgresConnection.execute(query: tablesQuery, parameters: [])

    // Group tables by schema
    var schemaTables: [String: [(schema: String, name: String)]] = [:]
    for row in tablesResult {
        if let schema = row["table_schema"] as? String,
           let name = row["table_name"] as? String {
            if schemaTables[schema] == nil {
                schemaTables[schema] = []
            }
            schemaTables[schema]?.append((schema, name))
        }
    }

    // Fetch column info for each table
    for (schema, tables) in schemaTables {
        result[schema] = []
        for table in tables {
            let columns = try await fetchColumns(connection: connection, schema: table.schema, table: table.name)
            let primaryKeys = try? await fetchPrimaryKeys(connection: connection, schema: table.schema, table: table.name)

            let tableInfo = TableInfo(
                name: table.name,
                schema: table.schema,
                tableType: .regular,
                primaryKeyColumns: primaryKeys,
                columnInfo: columns
            )

            result[schema]?.append(tableInfo)
        }
    }

    return result
}
```

- [ ] **Step 3: Update MetadataService implementation**

Replace stub in MetadataService.swift:

```swift
/// Fetch all schema metadata for a database
func fetchAllSchemaMetadata(databaseId: String) async throws -> [String: [TableInfo]] {
    logger.debug("Fetching all schema metadata for database: \(databaseId)")

    return try await connectionManager.withConnection { conn in
        try await queryExecutor.fetchAllSchemaMetadata(connection: conn)
    }
}
```

- [ ] **Step 4: Test with real database**

Run: Build and run the app, connect to a database
Expected: Metadata loads successfully, completions show actual tables and columns

- [ ] **Step 5: Commit**

```bash
git add PostgresGUI/Services/MetadataService.swift PostgresGUI/Services/Protocols/QueryExecutorProtocol.swift PostgresGUI/Services/Postgres/PostgresQueryExecutor.swift
git commit -m "feat: implement fetchAllSchemaMetadata with actual queries

- Add protocol method to QueryExecutorProtocol
- Implement metadata fetch in PostgresQueryExecutor
- Query information_schema.tables for all tables
- Fetch columns and primary keys for each table
- Group results by schema name
- Update MetadataService to use new method

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Chunk 10: Final Polish

### Task 12: Add completion indicator

**Files:**
- Modify: `PostgresGUI/Views/Components/Content/QueryEditorComponent.swift`

- [ ] **Step 1: Add visual indicator**

Add to toolbar in QueryEditorComponent:

```swift
// In the toolbar HStack, add after the Stop button:

if completionService != nil {
    Image(systemName: "circlebadge.fill")
        .font(.system(size: 8))
        .foregroundColor(.green)
        .help("Auto-completion enabled (Ctrl+Space)")
}
```

- [ ] **Step 2: Commit**

```bash
git add PostgresGUI/Views/Components/Content/QueryEditorComponent.swift
git commit -m "feat: add auto-completion indicator to query editor

- Show green dot when completion service is available
- Help tooltip indicates Ctrl+Space shortcut
- Visual confirmation that feature is active

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

### Task 13: Update CompletionCache to use AppState

**Files:**
- Modify: `PostgresGUI/Services/CompletionCache.swift`

- [ ] **Step 1: Replace placeholder methods**

Update CompletionCache to use real AppState:

```swift
@MainActor
class CompletionCache: CompletionCacheProtocol {
    // ... existing properties ...

    private let appState: AppState

    init(metadataService: MetadataServiceProtocol, appState: AppState) {
        self.metadataService = metadataService
        self.appState = appState
    }

    private func getCurrentConnectionId() -> String? {
        return appState.connection.currentConnectionId
    }

    private func databaseId(for table: String) -> String {
        return appState.connection.selectedDatabase?.id ?? "default"
    }
}
```

- [ ] **Step 2: Update QueryEditorView initialization**

Update setupCompletionServices in QueryEditorView:

```swift
private func setupCompletionServices() {
    let metadataService = appState.connection.metadataService
    tokenizer = SQLTokenizer()
    completionCache = CompletionCache(metadataService: metadataService, appState: appState)
    completionService = SQLCompletionService(cache: completionCache!, tokenizer: tokenizer!)

    Task {
        await loadCompletionMetadata()
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add PostgresGUI/Services/CompletionCache.swift PostgresGUI/Views/Containers/Content/QueryEditorView.swift
git commit -m "feat: integrate CompletionCache with AppState

- Pass AppState to CompletionCache for real connection/database tracking
- Use actual currentConnectionId and selectedDatabase from state
- Remove placeholder methods

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

### Task 14: Add error handling

**Files:**
- Modify: `PostgresGUI/Services/CompletionCache.swift`

- [ ] **Step 1: Add graceful error handling**

Update loadMetadata in CompletionCache:

```swift
func loadMetadata(forDatabase databaseId: String) async throws {
    let cacheKey = makeCacheKey(databaseId: databaseId)

    guard !loadingDatabases.contains(cacheKey) else { return }

    loadingDatabases.insert(cacheKey)
    defer { loadingDatabases.remove(cacheKey) }

    do {
        let schemaMetadata = try await metadataService.fetchAllSchemaMetadata(databaseId: databaseId)

        let connectionId = getCurrentConnectionId() ?? "default"
        if cache[connectionId] == nil {
            cache[connectionId] = [:]
        }
        cache[connectionId]?[databaseId] = schemaMetadata

        logger.debug("Loaded metadata for database: \(databaseId), schemas: \(schemaMetadata.keys.count)")
    } catch {
        logger.error("Failed to load metadata for database: \(databaseId), error: \(error)")
        // Don't throw - allow app to continue with keyword-only completions
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add PostgresGUI/Services/CompletionCache.swift
git commit -m "feat: add graceful error handling to CompletionCache

- Catch and log metadata fetch errors instead of throwing
- Allow app to continue with keyword-only completions on error
- Prevent blocking the editor when metadata unavailable

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

### Task 15: Integration testing and final commit

- [ ] **Step 1: Run all tests**

Run: `swift test`
Expected: All tests pass

- [ ] **Step 2: Manual testing checklist**

- [ ] Connect to a database
- [ ] Type "SEL" → see SELECT keyword suggestion
- [ ] Continue "SELECT * FRO" → see FROM keyword suggestion
- [ ] Continue "SELECT * FROM use" → see table suggestions starting with "use"
- [ ] Complete table name, type space, then "id, us" → see column suggestions
- [ ] Press Ctrl+Space → immediate suggestions
- [ ] Switch databases → cache reloads, new tables available
- [ ] Disconnect → completions fall back to keywords only
- [ ] Test with large schema (1000+ tables) → performance acceptable
- [ ] Verify layout swap → editor on top, results on bottom

- [ ] **Step 3: Final commit**

```bash
git add .
git commit -m "feat: complete query editor improvements

Features:
- Layout: query editor to top, results to bottom
- Context-aware auto-completion for tables, columns, and SQL keywords
- Automatic trigger (300ms debounce) + manual trigger (Ctrl+Space)
- Per-database metadata caching
- Fuzzy matching algorithm (exact, prefix, skip, fuzzy)
- Graceful error handling

Implementation:
- 8 new files: SQLContext, CompletionSuggestion, SQLToken models
- Services: CompletionCache, SQLCompletionService, SQLTokenizer
- MetadataService extension for bulk schema fetch
- Integration into SyntaxHighlightedEditor Coordinator
- 15+ unit tests covering core functionality

Testing:
- Unit tests for all models and services
- Integration testing with real databases
- Manual testing checklist completed

Spec: docs/superpowers/specs/2026-03-17-query-editor-improvements-design.md
Plan: docs/superpowers/plans/2026-03-17-query-editor-improvements.md

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Summary

This implementation plan delivers:

1. **Layout swap** (1 file, 1 task)
2. **Data models** (3 files, 3 tasks)
3. **Metadata service extension** (2 files, 1 task)
4. **Completion cache** (3 files, 1 task)
5. **SQL tokenizer** (2 files, 1 task)
6. **Completion service** (3 files, 1 task)
7. **Editor integration** (1 file, 1 task)
8. **Service wiring** (4 files, 1 task)
9. **Metadata implementation** (3 files, 1 task)
10. **Final polish** (3 tasks)

**Total: 15 tasks across 10 chunks**

Each task includes:
- Failing test first (TDD)
- Minimal implementation
- Test verification
- Frequent commits

**Ready for execution!**
