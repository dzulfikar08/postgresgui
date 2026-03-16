# Query Editor Improvements Design

**Date:** 2026-03-17
**Author:** Design brainstorming session
**Status:** Approved

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
- Implements NSTextViewDelegate completion methods
- Detects triggers (Ctrl+Space or automatic after 2+ chars)
- Displays completion popup and handles insertion
- Communicates with SQLCompletionService

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
- Automatic refresh on database changes
- Fast lookup by table/schema
- Lazy loading for large schemas

**Methods:**
- `getTables(forDatabase: String) -> [TableInfo]`
- `getColumns(forTable: String, inSchema: String) -> [ColumnInfo]`
- `invalidateDatabase(_ databaseId: String)`

#### SQLTokenizer (New File)
- Simple lexer for SQL keywords, identifiers, operators
- Determines cursor position context
- Handles quoted identifiers and schema prefixes

**Methods:**
- `tokenize(_ line: String) -> [SQLToken]`
- `getContext(at: NSRange, tokens: [SQLToken]) -> SQLContext`

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
- Keep existing resizable behavior

## Data Flow

### Auto-completion Flow

1. **Trigger Detection**
   - Automatic: User types 2+ characters, pauses 300ms
   - Manual: User presses Ctrl+Space

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
Database Switch
    ↓
Clear old cache
    ↓
Fetch tables for new database
    ↓
Store in CompletionCache
    ↓
Notify completion service ready
```

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
- **SQLCompletionService**: Context accuracy, suggestion filtering, ranking
- **CompletionCache**: Cache invalidation, per-database isolation

### Integration Tests
- Completion popup appearance and interaction
- Metadata refresh on database switch
- Insertion behavior (suffixes, replacements)
- Trigger detection (automatic and manual)

### Manual Testing
- Various database sizes (empty, medium, large schema)
- Automatic trigger responsiveness
- Ctrl+Space manual trigger in various contexts
- Layout swap doesn't break existing functionality
- Multi-database scenarios

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

- Layout successfully swapped with no broken functionality
- Auto-completion appears within 100ms of trigger
- Context detection accuracy > 90% for common SQL patterns
- No performance regression in editor responsiveness
- Graceful behavior when database not connected
