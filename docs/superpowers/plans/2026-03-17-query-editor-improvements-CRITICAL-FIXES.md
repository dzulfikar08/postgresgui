# Critical Fixes for Implementation Plan

**Date:** 2026-03-17
**Plan:** `docs/superpowers/plans/2026-03-17-query-editor-improvements.md`
**Status:** CRITICAL ISSUES FOUND - MUST FIX BEFORE IMPLEMENTATION

---

## Summary of Issues

The review of Chunks 3-10 found **5 critical blockers** that must be fixed:

1. **XCTest Usage in Chunks 4-6** (Tasks 6-8)
2. **Incomplete Mock Implementations**
3. **NSTextView Integration Issues** (Chunk 7)
4. **Placeholder Code** (Chunk 8)
5. **Constructor Signature Mismatches**

---

## Fix 1: Convert All Tests to Swift Testing Framework

### Affected Chunks: 4, 5, 6

**Problem:** Test files use `import XCTest` and `XCTestCase` instead of Swift Testing framework.

**Required Pattern:**

```swift
// ❌ WRONG (XCTest)
import XCTest
@testable import PostgresGUI

final class SomeTests: XCTestCase {
    var subject: SomeClass!

    override func setUp() {
        super.setUp()
        subject = SomeClass()
    }

    func testSomething() {
        XCTAssertEqual(subject.value, expected)
    }
}

// ✅ CORRECT (Swift Testing)
import Testing
@testable import PostgresGUI

@Suite("Some Tests")
struct SomeTests {
    var subject: SomeClass

    init() {
        subject = SomeClass()
    }

    @Test("Something works correctly")
    func something() {
        #expect(subject.value == expected)
    }
}
```

### Files to Fix:

1. **Chunk 4, Task 6, Step 2:** `PostgresGUITests/CompletionCacheTests.swift`
   - Change `import XCTest` → `import Testing`
   - Change `final class CompletionCacheTests: XCTestCase` → `@Suite("CompletionCache Tests") struct CompletionCacheTests`
   - Change `override func setUp()` → `init()`
   - Change all `XCTAssert*` → `#expect()`
   - Add `AppState` parameter to init (see Fix 2 below)

2. **Chunk 5, Task 7, Step 1:** `PostgresGUITests/SQLTokenizerTests.swift`
   - Same conversion pattern
   - Remove confusing `|` notation for cursor position
   - Use explicit `NSRange` parameters in tests

3. **Chunk 6, Task 8, Step 2:** `PostgresGUITests/SQLCompletionServiceTests.swift`
   - Same conversion pattern
   - Fix mock implementation (see Fix 2 below)

---

## Fix 2: Complete Mock Implementations

### Affected Chunks: 4, 6

**Problem:** Mock classes don't conform to their protocols and will cause compilation errors.

### Mock Metadata Service (Chunk 4)

**Current Code (Incomplete):**
```swift
class MockMetadataService: MetadataServiceProtocol {
    func fetchDatabases() async throws -> [DatabaseInfo] { return [] }
    func fetchPrimaryKeyColumns(schema: String, table: String) async throws -> [String] { return [] }
    func fetchColumnInfo(schema: String, table: String) async throws -> [ColumnInfo] { return [] }
    func fetchAllSchemaMetadata(databaseId: String) async throws -> [String: [TableInfo]] {
        return ["public": [TableInfo(...)]]
    }
}
```

**Fixed Code:**
```swift
actor MockMetadataService: MetadataServiceProtocol {
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
```

**Key Changes:**
- Add `actor` keyword for concurrency safety
- Return complete `ColumnInfo` objects with all required fields
- Include `tableType` parameter in `TableInfo`

### Mock Completion Cache (Chunk 6)

**Current Code (Missing):**
```swift
class MockCompletionCache {
    var tables: [TableInfo] = []
    var columns: [ColumnInfo] = []
}
```

**Fixed Code:**
```swift
actor MockCompletionCache: CompletionCacheProtocol {
    var tables: [TableInfo] = []
    var columns: [ColumnInfo] = []

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
```

---

## Fix 3: Correct NSTextView Integration

### Affected Chunk: 7, Task 9

**Problem 1:** `textView.complete(with:)` is not a valid NSTextView method.

**Problem 2:** Delegate method signature is incorrect.

**Problem 3:** Ctrl+Space handling is incomplete.

### Correct NSTextView Completion Approach

**Step: Replace incorrect showCompletionPopup method**

**Current (Wrong):**
```swift
private func showCompletionPopup(suggestions: [CompletionSuggestion], for partialWord: String) {
    guard let textView = textView else { return }

    // NSTextView will handle the completion popup
    // We need to provide the completion strings
    let completionStrings = suggestions.map { $0.text }

    // Trigger completion
    textView.complete(with: completionStrings)  // ❌ NOT A REAL METHOD
}
```

**Fixed (Correct):**
```swift
private func showCompletionPopup(suggestions: [CompletionSuggestion], for partialWord: String) {
    guard let textView = textView else { return }

    // Store suggestions for the delegate method to use
    self.currentCompletions = suggestions

    // Trigger the completion UI via NSTextView's built-in mechanism
    textView.complete(nil)
}

private var currentCompletions: [CompletionSuggestion] = []
```

### Fix Delegate Method Signature

**Current (Wrong):**
```swift
func textView(_ textView: NSTextView, completions: [String], forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String]?
```

**Fixed (Correct):**
```swift
func textView(_ textView: NSTextView, completions words: [String], forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String]? {
    guard let service = completionService else { return nil }

    let text = textView.string as NSString
    let partialWord = text.substring(with: charRange)
    let context = service.detectContext(at: charRange, inText: text as String)

    let suggestions = service.getCompletions(for: partialWord, inContext: context)

    // Store full suggestion objects
    self.currentCompletions = suggestions

    // Return only the text for NSTextView to display
    return suggestions.map { $0.text }
}
```

### Fix Ctrl+Space Handler

**Current (Incomplete):**
```swift
override func responds(to aSelector: Selector!) -> Bool {
    if aSelector == #selector(NSTextView.completions(forPartialWordRange:indexOfSelectedItem:)) {
        return true
    }
    return super.responds(to: aSelector)
}

@objc func triggerCompletionManually() {
    triggerCompletion()
}
```

**Fixed (Complete):**
```swift
// Add to Coordinator class:

// Track manual trigger requests
private var manualTriggerRequested = false

// Call this method to manually trigger completion
func triggerCompletionManually() {
    manualTriggerRequested = true
    triggerCompletion()
    manualTriggerRequested = false
}

// Modify triggerCompletion to handle manual trigger:
private func triggerCompletion() {
    guard let textView = textView else { return }

    // ... existing context detection code ...

    if manualTriggerRequested || partialWord.count >= 2 {
        // Show completions immediately if manually triggered
        // or after 2 characters for automatic trigger
        let suggestions = service.getCompletions(for: partialWord, inContext: context)
        guard !suggestions.isEmpty else { return }

        currentCompletions = suggestions
        textView.complete(nil)
    }
}
```

**Note:** The actual Ctrl+Space keyboard handling will be set up in the view layer (QueryEditorComponent) by adding a menu item or key equivalent.

---

## Fix 4: Complete Placeholder Code

### Affected Chunk: 8, Task 10

**Problem:** Incomplete code that won't compile.

### Location: Task 10, Step 1 (QueryEditorView modification)

**Current (Incomplete):**
```swift
private func setupCompletionServices() {
    let metadataService = // get from appState or create
    tokenizer = SQLTokenizer()
    completionCache = CompletionCache(metadataService: metadataService, appState: appState)
    completionService = SQLCompletionService(cache: completionCache!, tokenizer: tokenizer!)

    Task {
        await loadCompletionMetadata()
    }
}
```

**Fixed (Complete):**
```swift
private func setupCompletionServices() {
    // Get metadataService from connection state
    let metadataService = MetadataService(
        connectionManager: appState.connection.connectionManager,
        queryExecutor: appState.connection.queryExecutor
    )

    tokenizer = SQLTokenizer()
    completionCache = CompletionCache(
        metadataService: metadataService,
        appState: appState
    )
    completionService = SQLCompletionService(
        cache: completionCache!,
        tokenizer: tokenizer!
    )

    Task {
        await loadCompletionMetadata()
    }
}
```

### Location: Task 10, Step 2 (SyntaxHighlightedEditor parameter)

**Add to struct:**
```swift
struct SyntaxHighlightedEditor: NSViewRepresentable {
    @Binding var text: String
    @Environment(\.colorScheme) var colorScheme
    let completionService: SQLCompletionServiceProtocol?  // ← ADD THIS

    func makeNSView(context: Context) -> NSScrollView {
        // ... existing code ...
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self, completionService: completionService)  // ← UPDATE THIS
    }
}
```

---

## Fix 5: Constructor Signature Coordination

### Affected Chunks: 4, 13

**Problem:** `CompletionCache` init signature changes between Task 6 and Task 13, breaking tests.

### Solution: Use Final Signature from Task 13 in Task 6

**Task 6, Step 2 (Test Init) - Update to:**
```swift
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
```

**This ensures tests won't break when Task 13 updates the implementation.**

---

## Implementation Priority

Fix in this order:

1. **P0 - CRITICAL:** Fix XCTest → Swift Testing (Chunks 4, 5, 6)
2. **P0 - CRITICAL:** Complete mock implementations (Chunks 4, 6)
3. **P0 - CRITICAL:** Fix NSTextView integration (Chunk 7)
4. **P1 - HIGH:** Complete placeholder code (Chunk 8)
5. **P1 - HIGH:** Coordinate constructor signatures (Chunks 4, 13)

---

## Verification Checklist

After applying fixes, verify:

- [ ] All test files use `import Testing` (not XCTest)
- [ ] All test files use `@Suite` and `@Test` macros
- [ ] All assertions use `#expect()` (not XCTAssert*)
- [ ] All mocks conform to their protocols
- [ ] Mocks are `actor` classes for concurrency
- [ ] NSTextView completion API usage is correct
- [ ] No placeholder code remains (all implementations complete)
- [ ] Constructor signatures match between tests and final implementations

---

## Next Steps

1. Apply these fixes to the plan document
2. Re-run review on Chunks 3-10
3. Get approval for remaining chunks
4. Continue implementation with Chunk 3

---

**Estimated Time to Apply Fixes:** 30-45 minutes
**Risk if Not Fixed:** Implementation will fail with compilation errors and test failures
