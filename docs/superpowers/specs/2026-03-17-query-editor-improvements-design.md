# Query Editor Improvements Design

**Date:** 2026-03-17
**Author:** Design brainstorming session
**Status:** In Review (Round 2)
**Revision:** 1.1 - Fixed critical gaps from initial review

## Overview

This design describes improvements to the query editor in PostgresGUI:
1. **Layout change**: Move query editor to top pane, results to bottom pane
2. **Auto-completion**: Add context-aware table and column name completion

## Requirements

### Functional Requirements
- Swap vertical split view order (query editor top, results bottom)
- Provide automatic auto-completion after typing 2+ characters
- Support manual trigger via Ctrl+Space
- Show context-aware suggestions:
  - After SELECT: suggest columns
  - After FROM: suggest tables
  - After WHERE: suggest columns and operators
- Cache metadata per database
- Support fuzzy matching for table/column names

### Non-Functional Requirements
- Minimal performance impact (< 100ms for completion display)
- Graceful degradation when metadata unavailable
- Native macOS feel using NSTextView completion system

## Data Models

### SQLContext
```swift
enum SQLContext {
    case selectClause      // After SELECT, expecting columns
    case fromClause        // After FROM/JOIN, expecting tables
    case whereClause       // After WHERE, expecting columns/operators
    case tableReference    // After schema.table, expecting columns
    case default           // No specific context
}
```

### CompletionSuggestion
```swift
struct CompletionSuggestion: Identifiable {
    let id: String
    let text: String              // Text to insert
    let displayText: String       // Text to show in popup (may include type info)
    let kind: CompletionKind      // Table, column, keyword, etc.
    let relevanceScore: Int       // Higher = more relevant

    enum CompletionKind {
        case table
        case column
        case keyword
        case function
    }
}
```

### SQLToken
```swift
enum SQLToken {
    case keyword(String)
    case identifier(String)
    case operator(String)
    case stringLiteral(String)
    case whitespace
    case dot
    case comma
}
```

## Architecture

### Layout Changes

```
┌─────────────────────────────────────────────────┐
│           QueryEditorView (Top Pane)            │
│  - Editor toolbar with run/cancel buttons       │
│  - SyntaxHighlightedEditor with completions     │
├─────────────────────────────────────────────────┤
│         QueryResultsView (Bottom Pane)          │
│  - Results table or empty state                 │
└─────────────────────────────────────────────────┘
```

### Auto-completion Architecture

```
SyntaxHighlightedEditor (NSTextView)
         ↓
SQLCompletionDelegate
         ↓
SQLCompletionService
    ↓         ↓
SQLTokenizer  CompletionCache
```

**Key Components:**

1. **SQLCompletionDelegate** - NSTextView delegate that provides completions
2. **SQLCompletionService** - Business logic for SQL parsing and suggestions
3. **CompletionCache** - Caches TableInfo/ColumnInfo per database
4. **SQLTokenizer** - Parses SQL to determine completion context

## Components

### New Components

#### SQLCompletionDelegate (New File)
- **Implementation**: Integrated into SyntaxHighlightedEditor's existing Coordinator class
- Detects triggers (Ctrl+Space or automatic after 2+ chars with 300ms debounce)
- Implements NSTextView's `textView(_:completions:forPartialWordRange:indexOfSelectedItem:)` method
- Displays completion popup and handles insertion
- Communicates with SQLCompletionService
- **Thread Safety**: All operations on main thread (@MainActor isolation)

#### SQLCompletionService (New File)
**Responsibilities:**
- Parse current SQL line to determine context
- Query metadata cache for relevant tables/columns
- Filter and rank suggestions by partial input
- Support fuzzy matching for typos

**Methods:**
- `getCompletions(for: String, inContext: SQLContext) -> [CompletionSuggestion]`
- `detectContext(at: NSRange, inText: String) -> SQLContext`

#### CompletionCache (New File)
- Stores table/column metadata per database ID
- Cache key structure: `{connectionId}:{databaseId}`
- Automatic refresh on database changes via observation
- Fast lookup by table/schema
- Lazy loading for large schemas
- **Thread Safety**: @MainActor isolation, all access from main thread

**Methods:**
- `getTables(forDatabase: String) -> [TableInfo]`
- `getColumns(forTable: String, inSchema: String) -> [ColumnInfo]`
- `invalidateDatabase(_ databaseId: String)`
- `observeDatabaseChanges() // Subscribe to connection.selectedDatabase changes`

#### SQLTokenizer (New File)
- Simple lexer for SQL keywords, identifiers, operators
- Determines cursor position context
- Handles quoted identifiers and schema prefixes

**Methods:**
- `tokenize(_ line: String) -> [SQLToken]`
- `getContext(at: NSRange, tokens: [SQLToken]) -> SQLContext`

#### MetadataService Extension
Add new method to `MetadataServiceProtocol` for efficient bulk schema fetching:

```swift
extension MetadataServiceProtocol {
    /// Fetch all schema metadata for a database (tables and their columns)
    /// Used by auto-completion cache to populate suggestions
    func fetchAllSchemaMetadata(databaseId: String) async throws -> [String: [TableInfo]]
}
```

**Implementation:**
- Fetch all tables for the database
- For each table, fetch column info in parallel (with concurrency limit)
- Return dictionary keyed by schema name
- Cache results in CompletionCache

### Modified Components

#### SyntaxHighlightedEditor.swift
- Add completion delegate support
- Keep existing syntax highlighting behavior
- Expose NSTextView for completion integration

#### QueryEditorComponent.swift
- Add optional completion indicator (icon/text)
- Pass completion callbacks to editor

#### SplitContentView.swift
- Swap VSplitView children order
- Query editor first (top), results second (bottom)
- Rename variables for clarity: `topPaneView` → `editorPaneView`, `bottomPaneHeight` → `resultsPaneHeight`
- Keep existing resizable behavior
- No state management changes required

## Data Flow

### Auto-completion Flow

1. **Trigger Detection**
   - Automatic: User types 2+ characters, pauses 300ms
   - Manual: User presses Ctrl+Space (note: verify no macOS Input Method conflicts during implementation)

2. **Context Analysis**
   - Tokenize current line
   - Detect cursor position context (SELECT, FROM, WHERE, etc.)
   - Identify relevant tables (e.g., FROM clause tables)

3. **Suggestion Generation**
   - Query cache for context-appropriate items
   - Filter by partial input (fuzzy matching)
   - Rank by relevance (exact match, prefix match, fuzzy match)

4. **Display & Selection**
   - Show popup with suggestions
   - User navigates with arrows or continues typing
   - Press Enter/Tab to insert

5. **Insertion**
   - Replace partial word with selected completion
   - Add appropriate suffix (space, parenthesis, comma)

### Metadata Cache Flow

```
User switches database
    ↓
CompletionCache observes connection.selectedDatabase change
    ↓
Invalidate old cache entries
    ↓
Call MetadataService.fetchAllSchemaMetadata() in background
    ↓
Store results in cache with key {connectionId}:{databaseId}
    ↓
Notify completion service ready for new database
```

### Fuzzy Matching Algorithm

**Algorithm:** Case-insensitive prefix matching with character skip tolerance

**Rules:**
1. **Exact match** (highest priority): `username` matches `username` exactly
2. **Prefix match** (high priority): `usr` matches `username` (starts with usr)
3. **Skip match** (medium priority): `usrnm` matches `username` (characters in order, allows gaps)
4. **Fuzzy match** (low priority): `usrnme` matches `username` (allows 1 typo/transposition)

**Scoring:**
- Exact match: 100 points
- Prefix match: 80 points
- Skip match: 60 points
- Fuzzy match: 40 points

Only show matches with score ≥ 40, sorted by score descending.

### Layout Change Flow

- Simple reordering in SplitContentView body
- No state management changes required
- Existing bindings work identically

## Error Handling

### No Database Selected
- Auto-completion silently disabled
- Show subtle hint: "Connect to a database for auto-completion"

### Metadata Fetch Failure
- Fall back to SQL keyword completions only
- Log error for debugging
- Don't block editor or show errors

### Large Schema (1000+ tables)
- Lazy load column info on-demand
- Limit suggestions to top 50 matches
- Show loading indicator during initial fetch

### Invalid SQL Syntax
- Best-effort parsing - provide completions anyway
- Don't show syntax errors to user

### Performance Issues
- Debounce automatic completion (300ms)
- Cache SQL parse results per line
- Asynchronous metadata fetching
- Cancel pending requests on new trigger

## SQL Context Types

The completion system detects these contexts:

| Context | Trigger | Suggestions |
|---------|---------|-------------|
| SELECT_CLAUSE | After SELECT keyword | Column names from known tables |
| FROM_CLAUSE | After FROM/JOIN keywords | Table names |
| WHERE_CLAUSE | After WHERE keyword | Column names, operators |
| TABLE_REFERENCE | After schema dot (.) | Column names from that table |
| DEFAULT | No specific context | Keywords, table names |

## Testing Strategy

### Unit Tests
- **SQLTokenizer**: Keyword detection, identifier parsing, context detection
  - Test cases: 20+ SQL patterns covering SELECT, FROM, WHERE, JOIN contexts
  - Edge cases: quoted identifiers, schema prefixes, comments
- **SQLCompletionService**: Context accuracy, suggestion filtering, ranking
  - Test cases: Verify correct context detection for 30+ SQL patterns
  - Fuzzy matching test cases: 50+ input/completion pairs
- **CompletionCache**: Cache invalidation, per-database isolation
  - Test cases: Database switch clears cache, concurrent access safety

### Integration Tests
- Completion popup appearance and interaction
- Metadata refresh on database switch
- Insertion behavior (suffixes, replacements)
- Trigger detection (automatic and manual)

### Performance Benchmarks
- **Completion display time**: < 100ms for 50 suggestions (measured with XCTestMetrics)
- **Large schema test**: Database with 1000 tables, 100 columns each
  - Initial metadata fetch: < 3 seconds
  - Completion lookup: < 50ms (cached)
  - Memory usage: < 50MB for cached metadata
- **Automatic trigger responsiveness**: No typing lag with 300ms debounce

### Manual Testing
- Various database sizes (empty, medium, large schema with 1000+ tables)
- Automatic trigger responsiveness
- Ctrl+Space manual trigger in various contexts
- Layout swap doesn't break existing functionality
- Multi-database scenarios
- **Context detection accuracy test**: Run 50 common SQL patterns, verify > 90% accuracy

## Implementation Notes

### Priority 1 (Core Features)
1. Layout swap in SplitContentView
2. Basic completion delegate with Ctrl+Space trigger
3. Simple context detection (SELECT, FROM)
4. Table name completion from metadata

### Priority 2 (Enhanced Features)
1. Automatic trigger with debouncing
2. Column name completion
3. All SQL contexts (WHERE, JOIN, etc.)
4. Per-database caching

### Priority 3 (Polish)
1. Fuzzy matching
2. Loading indicators
3. Performance optimizations for large schemas
4. Completion settings/preferences

## Success Criteria

### Functional
- Layout successfully swapped with no broken functionality (all existing tests pass)
- Auto-completion appears within 100ms of trigger (measured via XCTestMetrics)
- Context detection accuracy ≥ 90% for common SQL patterns (50 test cases)
- Graceful behavior when database not connected (no crashes, silent fallback)

### Performance
- Completion display: < 100ms for 50 suggestions
- Large schema (1000 tables): Initial fetch < 3s, cached lookup < 50ms
- Memory usage: < 50MB for cached metadata
- No typing lag with automatic trigger (300ms debounce)
- Editor responsiveness: No regression from baseline (measured via Instruments)

### Test Coverage
- Unit tests for SQLTokenizer, SQLCompletionService, CompletionCache
- Integration tests for completion popup and metadata refresh
- Performance benchmarks pass all targets
- Manual testing checklist completed
