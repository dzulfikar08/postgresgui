# SqlServerGUI Design Specification

**Date**: 2026-03-17
**Author**: Claude (with user input)
**Status**: Draft

## 1. Overview

### 1.1 Goal

Create a standalone, native SQL Server client application for macOS that provides full feature parity with PostgresGUI.

### 1.2 Scope

- Complete rewrite of PostgresGUI adapted for SQL Server
- Full feature set: query editor, table browser, row editing, saved queries, connection management, etc.
- New SqlServerNIO driver (FreeTDS wrapper)
- Separate codebase in `SqlServerGUI` folder

### 1.3 Success Criteria

**MVP Success Criteria**:
- Connect to SQL Server (local and remote)
- Execute SELECT queries and display results
- Browse databases, tables, and schemas
- View table structure (columns, types, keys)
- Edit/delete rows with primary keys
- Save and manage connection profiles
- Execute custom SQL scripts

**Full Feature Parity Criteria**:
- All PostgresGUI features working for SQL Server
- Performance comparable to PostgresGUI
- Robust error handling
- User-friendly error messages

## 2. Architecture

### 2.1 High-Level Architecture

SqlServerGUI will mirror PostgresGUI's service-based architecture with three main layers:

```
┌─────────────────────────────────────────┐
│         SwiftUI Views Layer             │
│   (QueryEditor, TableBrowser, etc.)     │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│      ViewModels & State Layer           │
│  (Observable ViewModels, AppState)      │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│         Services Layer                  │
│  ┌──────────────────────────────────┐  │
│  │  DatabaseService                 │  │
│  │  ├─ ConnectionManager (TDS)      │  │
│  │  ├─ QueryExecutor (T-SQL)        │  │
│  │  └─ Specialized Services:        │  │
│  │     • TableService               │  │
│  │     • MetadataService            │  │
│  │     • RowOperationsService       │  │
│  └──────────────────────────────────┘  │
└─────────────────────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│      SqlServerNIO (FreeTDS Wrapper)     │
│   Swift C Interop → FreeTDS Library     │
└─────────────────────────────────────────┘
```

### 2.2 Key Components

1. **SqlServerNIO** (New Swift Package)
   - Swift async/await wrapper around FreeTDS
   - Connection management with connection pooling
   - Query execution with prepared statements
   - Type conversion between SQL Server and Swift types

2. **Services Layer** (Adapted from PostgresGUI)
   - All existing services rewritten for SQL Server
   - Same protocols and interfaces
   - SQL Server-specific metadata queries

3. **UI Layer** (Copied from PostgresGUI)
   - Minimal changes to SwiftUI views
   - Updated connection form for SQL Server parameters
   - SQL Server-specific terminology

## 3. SqlServerNIO Driver Design

### 3.1 Core Architecture

```swift
// Main protocol (mirrors PostgresConnectionManager)
protocol SQLServerConnectionManagerProtocol {
    func connect(...) async throws
    func disconnect() async
    func withConnection<T>(_ operation: (Connection) async throws -> T) async throws -> T
}

// FreeTDS wrapper
actor SQLServerConnectionManager: SQLServerConnectionManagerProtocol {
    private var connection: UnsafeMutablePointer<DBPROCESS>?

    func connect(...) async throws {
        // FreeTDS dbinit() → dbopen() → dbuse()
    }

    func executeQuery(_ sql: String) async throws -> ([Row], [String]) {
        // dbcmd() → dbsqlexec() → dbresults() → dbnextrow()
    }
}
```

### 3.2 C Interop Layer

- Use Swift's modulemap for FreeTDS headers (`sybdb.h`, `dblib.h`)
- Safe wrappers around unsafe C pointers
- Proper memory management and cleanup

### 3.3 Connection Management

- Connection pooling for efficiency
- Async/await wrappers (FreeTDS is synchronous)
- Timeout and cancellation support

### 3.4 Type Mapping

| SQL Server Type | Swift Type |
|----------------|------------|
| BIT | Bool |
| TINYINT | Int |
| SMALLINT | Int |
| INT | Int |
| BIGINT | Int64 |
| VARCHAR/NVARCHAR | String |
| CHAR/NCHAR | String |
| DATETIME/DATETIME2 | Date |
| DATETIMEOFFSET | Date with timezone |
| DECIMAL/NUMERIC | Decimal |
| FLOAT/REAL | Double |
| VARBINARY/BINARY | Data |
| UNIQUEIDENTIFIER | UUID |
| XML | String |
| TEXT/NTEXT | String |

### 3.5 SQL Server-Specific Features

- Windows Authentication (SSPI)
- Encrypted connections (TLS)
- Multiple result sets support
- TDS protocol version negotiation

## 4. Services Layer Adaptations

### 4.1 Services to Rewrite

All services from PostgresGUI will be adapted with SQL Server-specific implementations:

| Service | PostgresGUI | SqlServerGUI |
|---------|-------------|--------------|
| **DatabaseService** | `fetchDatabases()` | `fetchDatabases()` (queries sys.databases) |
| **MetadataService** | `pg_catalog`, `information_schema` | `sys.objects`, `sys.columns`, `sys.indexes` |
| **TableService** | `pg_class`, `pg_attribute` | `sys.tables`, `sys.columns`, `sys.schemas` |
| **QueryExecutor** | PostgreSQL prepared statements | T-SQL prepared statements |
| **RowOperationsService** | PostgreSQL RETURNING clause | OUTPUT clause for INSERT/UPDATE |

### 4.2 Key Metadata Query Examples

**List Tables:**
```sql
-- PostgresGUI
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema NOT IN ('pg_catalog', 'information_schema')

-- SqlServerGUI
SELECT s.name AS schema_name, t.name AS table_name
FROM sys.tables t
INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
WHERE s.name NOT IN ('sys', 'INFORMATION_SCHEMA')
ORDER BY s.name, t.name
```

**Get Column Information:**
```sql
-- PostgresGUI
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = $1 AND table_name = $2

-- SqlServerGUI
SELECT
    c.name AS column_name,
    TYPE_NAME(c.user_type_id) AS data_type,
    c.is_nullable,
    c.default_value
FROM sys.columns c
INNER JOIN sys.tables t ON c.object_id = t.object_id
INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
WHERE s.name = $1 AND t.name = $2
```

**Get Primary Keys:**
```sql
-- PostgresGUI
SELECT a.attname AS column_name
FROM pg_index i
JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)

-- SqlServerGUI
SELECT c.name AS column_name
FROM sys.indexes i
INNER JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
WHERE i.is_primary_key = 1
AND OBJECT_SCHEMA_NAME(i.object_id) = $1
AND OBJECT_NAME(i.object_id) = $2
```

### 4.3 Connection Parameter Differences

| Parameter | PostgresGUI | SqlServerGUI |
|-----------|-------------|--------------|
| Default Port | 5432 | 1433 |
| Default Database | postgres | master |
| SSL Modes | disable, allow, prefer, require | None, Encrypt, Trust |
| Auth Methods | Password only | Password + Windows Auth (SSPI) |
| Connection String | libpq format | Server/database format |
| Schema | public | dbo |

## 5. UI Layer Changes

### 5.1 Views Requiring Changes

1. **ConnectionFormView**
   - Add authentication type picker (SQL Server Auth / Windows Auth)
   - Update default port to 1433
   - Add "Trust Server Certificate" toggle
   - Update SSL mode options (None, Encrypt, Trust)

2. **ConnectionProfile Model**
```swift
enum AuthenticationType {
    case sqlServer
    case windowsIntegrated
}

struct ConnectionProfile {
    var authenticationType: AuthenticationType = .sqlServer
    var trustServerCertificate: Bool = false
    // ... other fields
}
```

### 5.2 Views Requiring No Changes

- RootView, TabView, QueryEditorView
- QueryResultsView, TableContentView
- SavedQueriesView, SettingsView

### 5.3 Asset Updates

- App icon: Replace PostgreSQL elephant with SQL Server logo
- App name: "PostgresGUI" → "SqlServerGUI"
- Bundle identifier: `com.postgresgui.app` → `com.sqlservergui.app`

## 6. Project Structure

```
SqlServerGUI/
├── SqlServerGUI.xcodeproj          # New Xcode project
├── SqlServerGUI/                   # Main app target
│   ├── SqlServerGUIApp.swift       # App entry point
│   ├── Views/                      # Copied from PostgresGUI
│   ├── ViewModels/                 # Copied from PostgresGUI
│   ├── Models/                     # Copied from PostgresGUI
│   ├── Services/                   # Adapted for SQL Server
│   │   ├── DatabaseService.swift
│   │   ├── ConnectionService.swift
│   │   ├── MetadataService.swift   # SQL Server queries
│   │   └── ...
│   ├── State/                      # Copied from PostgresGUI
│   ├── Errors/                     # Updated for SQL Server
│   └── Assets.xcassets/            # New SQL Server icons
├── SqlServerNIO/                   # New Swift Package
│   ├── Sources/SqlServerNIO/
│   │   ├── ConnectionManager.swift     # FreeTDS wrapper
│   │   ├── QueryExecutor.swift         # T-SQL execution
│   │   ├── TypeConversion.swift        # SQL Server ↔ Swift
│   │   ├── FreeTDSInterop.swift        # C interop
│   │   └── Exports.swift               # Public API
│   ├── Package.swift
│   └── include/
│       └── freetds/
│           ├── sybdb.h              # FreeTDS headers
│           └── dblib.h
├── build_dmg.sh                    # DMG build script
└── README.md                       # SQL Server specific docs
```

## 7. Implementation Plan

### 7.1 Phase 1: Foundation (Week 1-2)

**Goal**: Basic SQL Server connectivity

- Create SqlServerNIO package structure
- Implement FreeTDS C interop layer
- Basic connection (host, port, username, password)
- Simple query execution (SELECT)
- Core type conversion (int, string, bool, date)

### 7.2 Phase 2: Core Services (Week 3-4)

**Goal**: Database and table browsing

- Implement DatabaseService (fetchDatabases)
- Implement MetadataService (schemas, tables, columns)
- SQL Server system catalog queries
- Connection management (connect, disconnect, test)
- Error handling and user-friendly messages

### 7.3 Phase 3: UI Adaptation (Week 5)

**Goal**: Functional GUI

- Copy SwiftUI views from PostgresGUI
- Update connection form for SQL Server parameters
- Test basic workflows (connect, browse tables, run query)
- Update app branding (name, icon, bundle ID)

### 7.4 Phase 4: Advanced Features (Week 6-7)

**Goal**: Full feature parity

- Row editing with OUTPUT clause
- Saved queries management
- Table operations (truncate, drop, generate DDL)
- Query history
- Multiple result sets support

### 7.5 Phase 5: Polish & Testing (Week 8)

**Goal**: Production-ready application

- Comprehensive error handling
- Performance optimization
- Edge case testing
- Documentation
- DMG packaging and distribution

## 8. Risk Assessment

### 8.1 Technical Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| **FreeTDS Swift interop complexity** | High | Start with simple queries, build up gradually; thorough testing |
| **Windows Auth (SSPI) on macOS** | Medium | Focus on SQL Server auth first; Windows Auth may require additional research |
| **T-SQL syntax differences** | Low | Well-documented; most queries are straightforward adaptations |
| **Type conversion edge cases** | Medium | Comprehensive test coverage; handle NULL values explicitly |
| **FreeTDS installation on user machines** | High | Bundle FreeTDS library with app or provide clear installation instructions |

### 8.2 FreeTDS Distribution Strategy

**Option A**: Bundle FreeTDS dylib with app (recommended for production)
- Use `install_name_tool` to fix library paths
- Include in app bundle Resources
- Self-contained distribution

**Option B**: Require Homebrew FreeTDS (recommended for development)
- Simpler development
- Requires user action
- Better for updates

**Recommendation**: Start with Option B for development, evaluate Option A for production.

## 9. Dependencies

### 9.1 External Dependencies

- **FreeTDS**: Database library for SQL Server connectivity
- **SwiftNIO**: Async networking foundation (inherited from PostgresGUI)
- **SwiftData**: Local data persistence (inherited from PostgresGUI)

### 9.2 Development Dependencies

- Xcode 16.0+
- macOS 15.0+
- Swift 6.0+
- Homebrew (for FreeTDS during development)

## 10. Testing Strategy

### 10.1 Unit Testing

- Type conversion tests (all SQL Server types → Swift types)
- Metadata query tests (mock results)
- Connection state management tests

### 10.2 Integration Testing

- Test against actual SQL Server instances:
  - Local SQL Server (Docker/VM)
  - Remote SQL Server (Azure SQL Database)
- Test all metadata queries
- Test CRUD operations

### 10.3 UI Testing

- SwiftUI tests for critical user flows
- Manual testing for complex interactions

## 11. Documentation

### 11.1 Developer Documentation

- SqlServerNIO API documentation
- Architecture diagrams
- Contribution guidelines

### 11.2 User Documentation

- Installation instructions
- Connection setup guide
- Feature documentation
- Troubleshooting guide

## 12. Success Metrics

### 12.1 Functional Metrics

- All PostgresGUI features working for SQL Server
- Support for SQL Server 2016+
- Compatible with Azure SQL Database

### 12.2 Performance Metrics

- Connection time < 2 seconds (local)
- Query response time comparable to PostgresGUI
- Memory footprint similar to PostgresGUI

### 12.3 Quality Metrics

- Zero crashes on basic workflows
- Clear error messages for all failure modes
- Smooth user experience

## Appendix A: SQL Server System Catalog Reference

Key system views for metadata queries:

- `sys.databases` - List databases
- `sys.tables` - List tables
- `sys.views` - List views
- `sys.schemas` - List schemas
- `sys.columns` - Column information
- `sys.indexes` - Index information
- `sys.key_constraints` - Key constraints
- `sys.foreign_keys` - Foreign keys
- `INFORMATION_SCHEMA.COLUMNS` - Standard column info
- `INFORMATION_SCHEMA.TABLES` - Standard table info

## Appendix B: T-SQL vs PostgreSQL Quick Reference

| Operation | PostgreSQL | T-SQL |
|-----------|-----------|-------|
| Limit results | `LIMIT 10` | `SELECT TOP 10 *` |
| String concatenation | `||` | `+` |
| Current timestamp | `NOW()` | `GETDATE()` |
| Auto-increment | `SERIAL` | `IDENTITY(1,1)` |
| Returning data | `RETURNING *` | `OUTPUT INSERTED.*` |
| String literal | `'text'` | `'text'` (same) |
| Boolean type | `BOOLEAN` | `BIT` |
| Schema delimiter | `.` | `.` (same) |
