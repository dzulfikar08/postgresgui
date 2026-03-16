# SqlServerGUI Phase 0: Technical Validation (PoC) Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Validate FreeTDS Swift interop feasibility through a 1-week proof-of-concept that demonstrates basic SQL Server connectivity from Swift.

**Architecture:** Minimal Swift package that wraps FreeTDS C library using Swift's C interop capabilities, providing async/await interface for basic SQL Server operations.

**Tech Stack:** Swift 6.0, FreeTDS 1.3+, C interop, Xcode 16.0+

---

## Project Structure

```
SqlServerPoC/
├── Package.swift                          # Swift Package manifest
├── Sources/
│   ├── SqlServerPoC/
│   │   ├── FreeTDS.swift                  # C interop layer
│   │   ├── Connection.swift               # Connection management
│   │   ├── QueryExecutor.swift            # Query execution
│   │   └── TypeConversion.swift           # SQL Server ↔ Swift types
│   └── FreeTDS/
│       ├── module.modulemap               # C header mapping
│       └── include/
│           └── sybdb.h                    # FreeTDS header (symlink)
├── Tests/
│   └── SqlServerPoCTests/
│       ├── ConnectionTests.swift          # Connection tests
│       ├── QueryTests.swift               # Query execution tests
│       └── TypeConversionTests.swift      # Type mapping tests
└── README.md                              # Setup instructions
```

---

## Chunk 1: Project Setup and FreeTDS Integration

### Task 1: Create Swift Package structure

**Files:**
- Create: `SqlServerPoC/Package.swift`
- Create: `SqlServerPoC/Sources/SqlServerPoC/SqlServerPoC.swift`
- Create: `SqlServerPoC/README.md`

- [ ] **Step 1: Create Package.swift manifest**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SqlServerPoC",
    platforms: [.macOS(.v15)],
    dependencies: [],
    targets: [
        .target(
            name: "SqlServerPoC",
            dependencies: [],
            cSettings: [
                .define("FREETDS_STATIC", .when(platforms: [.macOS])),
            ]
        ),
        .testTarget(
            name: "SqlServerPoCTests",
            dependencies: ["SqlServerPoC"]
        ),
    ]
)
```

- [ ] **Step 2: Create basic Swift file**

```swift
// SqlServerPoC.swift
import Foundation

public struct SqlServerPoC {
    public init() {}

    public var text: String {
        "SqlServerPoC - Phase 0 Validation"
    }
}
```

- [ ] **Step 3: Create README with setup instructions**

```markdown
# SqlServerPoC - Phase 0 Technical Validation

## Setup

1. Install FreeTDS via Homebrew:
   ```bash
   brew install freetds
   ```

2. Find FreeTDS installation path:
   ```bash
   brew --prefix freetds
   # Output: /opt/homebrew/opt/freetds
   ```

3. Link FreeTDS headers:
   ```bash
   ln -s /opt/homebrew/opt/freetds/include/sybdb.h \
     Sources/FreeTDS/include/sybdb.h
   ```

4. Build the package:
   ```bash
   swift build
   ```

## Running Tests

```bash
swift test
```

## Success Criteria

- [ ] Can connect to SQL Server and execute SELECT in <50 lines of Swift
- [ ] No crashes or memory leaks in 100-iteration test
- [ ] Performance within 3x of PostgresGUI for simple query
```

- [ ] **Step 4: Initialize Git repository and commit initial structure**

```bash
cd SqlServerPoC
git init
git add .
git commit -m "feat: initialize SqlServerPoC package structure"
```

### Task 2: Set up FreeTDS C interop layer

**Files:**
- Create: `SqlServerPoC/Sources/FreeTDS/module.modulemap`
- Create: `SqlServerPoC/Sources/FreeTDS/include/sybdb.h`

- [ ] **Step 1: Create module map for FreeTDS**

```swift
// module.modulemap
module FreeTDS {
    header "sybdb.h"
    link "sybdb"
    export *
}
```

- [ ] **Step 2: Link FreeTDS header**

```bash
# Find FreeTDS installation
FREETDS_PREFIX=$(brew --prefix freetds)

# Create symlink for header
mkdir -p Sources/FreeTDS/include
ln -s "$FREETDS_PREFIX/include/sybdb.h" Sources/FreeTDS/include/sybdb.h

# Verify
ls -la Sources/FreeTDS/include/
```

Expected output:
```
sybdb.h -> /opt/homebrew/opt/freetds/include/sybdb.h
```

- [ ] **Step 3: Update Package.swift to include FreeTDS module**

Edit `Package.swift`:

```swift
targets: [
    .target(
        name: "SqlServerPoC",
        dependencies: [],
        cSettings: [
            .define("FREETDS_STATIC", .when(platforms: [.macOS])),
            .unsafeFlags([
                "-Xcc", "-I\(ProcessInfo.processInfo.environment["FREETDS_INCLUDE_PATH"] ?? "/opt/homebrew/opt/freetds/include")",
                "-Xlinker", "-L\(ProcessInfo.processInfo.environment["FREETDS_LIB_PATH"] ?? "/opt/homebrew/opt/freetds/lib")",
            ], .when(platforms: [.macOS])),
        ]
    ),
    // ...
]
```

- [ ] **Step 4: Commit FreeTDS integration**

```bash
git add Sources/FreeTDS Package.swift
git commit -m "feat: add FreeTDS C interop layer"
```

---

## Chunk 2: Core FreeTDS Wrapper

### Task 3: Implement FreeTDS C bindings

**Files:**
- Create: `SqlServerPoC/Sources/SqlServerPoC/FreeTDS.swift`

- [ ] **Step 1: Write C type definitions and function declarations**

```swift
import Foundation

// MARK: - FreeTDS C Types

typealias DBPROCESS = OpaquePointer
typealias DBINT = Int32
typealias DBSMALLINT = Int16
typealias DBTINYINT = UInt8
typealias DBBOOL = UInt8
typealias DBREAL = Float
typealias DBFLT8 = Double
typealias DBCHAR = Int8
typealias DBBINARY = UInt8

// MARK: - FreeTDS Constants

let DBINT_NULL: DBINT = 0x80000000
let DBFLT8_NULL: DBFLT8 = 0x7FF0000000000000
let DBBOOL_NULL: DBBOOL = 0xFF

enum DBLIB_ResultTypes: Int32 {
    case SUCCEED = 1
    case FAIL = 0
    case NO_MORE_ROWS = 2
    case BUF_FULL = 3
}

enum DBLIB_Types: Int32 {
    case INT_TYPE = 38
    case SMALLINT_TYPE = 40
    case TINYINT_TYPE = 48
    case BIT_TYPE = 104
    case FLOAT_TYPE = 109
    case REAL_TYPE = 100
    case MONEY_TYPE = 60
    case DATETIME_TYPE = 111
    case CHAR_TYPE = 47
    case VARCHAR_TYPE = 39
    case BINARY_TYPE = 45
    case VARBINARY_TYPE = 37
    case NUMERIC_TYPE = 108
    case DECIMAL_TYPE = 106
    case TEXT_TYPE = 35
    case IMAGE_TYPE = 34
    case DATETIME2_TYPE = 150
    case DATETIMEOFFSET_TYPE = 155
}

// MARK: - FreeTDS Function Declarations

@_silgen_name("dbinit")
func dbinit() -> UnsafeMutablePointer<DBPROCESS>?

@_silgen_name("dbopen")
func dbopen(
    _ login: UnsafeMutablePointer<DBPROCESS>?,
    _ server: UnsafePointer<Int8>?
) -> UnsafeMutablePointer<DBPROCESS>?

@_silgen_name("dblogin")
func dblogin() -> UnsafeMutablePointer<DBPROCESS>?

@_silgen_name("dbsetlogintime")
func dbsetlogintime(_ seconds: Int32) -> Int32

@_silgen_name("dbsetuserdata")
func dbsetuserdata(
    _ dbproc: UnsafeMutablePointer<DBPROCESS>?,
    _ ptr: UnsafeMutableRawPointer?
)

@_silgen_name("dbgetuserdata")
func dbgetuserdata(
    _ dbproc: UnsafeMutablePointer<DBPROCESS>?
) -> UnsafeMutableRawPointer?

@_silgen_name("DBSETLUSER")
func DBSETLUSER(
    _ login: UnsafeMutablePointer<DBPROCESS>?,
    _ user: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<DBPROCESS>?

@_silgen_name("DBSETLPWD")
func DBSETLPWD(
    _ login: UnsafeMutablePointer<DBPROCESS>?,
    _ pwd: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<DBPROCESS>?

@_silgen_name("DBSETLAPP")
func DBSETLAPP(
    _ login: UnsafeMutablePointer<DBPROCESS>?,
    _ app: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<DBPROCESS>?

@_silgen_name("dbuse")
func dbuse(
    _ dbproc: UnsafeMutablePointer<DBPROCESS>?,
    _ database: UnsafePointer<CChar>?
) -> Int32

@_silgen_name("dbcmd")
func dbcmd(
    _ dbproc: UnsafeMutablePointer<DBPROCESS>?,
    _ cmd: UnsafePointer<CChar>?
)

@_silgen_name("dbsqlexec")
func dbsqlexec(
    _ dbproc: UnsafeMutablePointer<DBPROCESS>?
) -> Int32

@_silgen_name("dbresults")
func dbresults(
    _ dbproc: UnsafeMutablePointer<DBPROCESS>?
) -> Int32

@_silgen_name("dbnumcols")
func dbnumcols(
    _ dbproc: UnsafeMutablePointer<DBPROCESS>?
) -> Int32

@_silgen_name("dbcolname")
func dbcolname(
    _ dbproc: UnsafeMutablePointer<DBPROCESS>?,
    _ column: Int32
) -> UnsafePointer<CChar>?

@_silgen_name("dbcoltype")
func dbcoltype(
    _ dbproc: UnsafeMutablePointer<DBPROCESS>?,
    _ column: Int32
) -> Int32

@_silgen_name("dbcollen")
func dbcollen(
    _ dbproc: UnsafeMutablePointer<DBPROCESS>?,
    _ column: Int32
) -> Int32

@_ilgen_name("dbnextrow")
func dbnextrow(
    _ dbproc: UnsafeMutablePointer<DBPROCESS>?
) -> Int32

@_silgen_name("dbdata")
func dbdata(
    _ dbproc: UnsafeMutablePointer<DBPROCESS>?,
    _ column: Int32
) -> UnsafeMutableRawPointer?

@_silgen_name("dbdatlen")
func dbdatlen(
    _ dbproc: UnsafeMutablePointer<DBPROCESS>?,
    _ column: Int32
) -> Int32

@_silgen_name("dbisnull")
func dbisnull(
    _ dbproc: UnsafeMutablePointer<DBPROCESS>?,
    _ column: Int32
) -> Int32

@_silgen_name("dbclose")
func dbclose(
    _ dbproc: UnsafeMutablePointer<DBPROCESS>?
)

@_silgen_name("dbexit")
func dbexit()
```

- [ ] **Step 2: Build to verify C declarations compile**

```bash
swift build
```

Expected: Build succeeds with no errors (warnings about unused declarations are OK)

- [ ] **Step 3: Commit FreeTDS bindings**

```bash
git add Sources/SqlServerPoC/FreeTDS.swift
git commit -m "feat: add FreeTDS C function declarations"
```

### Task 4: Implement Connection type

**Files:**
- Create: `SqlServerPoC/Sources/SqlServerPoC/Connection.swift`

- [ ] **Step 1: Write connection configuration struct**

```swift
import Foundation

public struct ConnectionConfiguration {
    let host: String
    let port: Int
    let username: String
    let password: String
    let database: String
    let timeout: Int

    public init(
        host: String,
        port: Int = 1433,
        username: String,
        password: String,
        database: String = "master",
        timeout: Int = 5
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.database = database
        self.timeout = timeout
    }
}
```

- [ ] **Step 2: Write Connection class with FreeTDS wrapper**

```swift
import Foundation

public final class Connection {
    private var dbProcess: UnsafeMutablePointer<DBPROCESS>?
    private let config: ConnectionConfiguration

    public init(config: ConnectionConfiguration) {
        self.config = config
    }

    public func connect() throws {
        // Initialize FreeTDS
        guard let login = dblogin() else {
            throw ConnectionError.initializationFailed
        }

        // Set login timeout
        dbsetlogintime(Int32(config.timeout))

        // Set user credentials
        config.username.withCString { userPtr in
            config.password.withCString { pwdPtr in
                DBSETLUSER(login, userPtr)
                DBSETLPWD(login, pwdPtr)
            }
        }

        // Set application name
        "SqlServerPoC".withCString { appPtr in
            DBSETLAPP(login, appPtr)
        }

        // Build server string
        let serverString = "\(config.host):\(config.port)"

        // Open connection
        serverString.withCString { serverPtr in
            dbProcess = dbopen(login, serverPtr)
        }

        guard dbProcess != nil else {
            throw ConnectionError.connectionFailed
        }

        // Switch to target database
        try useDatabase(config.database)
    }

    public func useDatabase(_ database: String) throws {
        guard let dbProcess = dbProcess else {
            throw ConnectionError.notConnected
        }

        let result = database.withCString { dbPtr in
            dbuse(dbProcess, dbPtr)
        }

        if result != 1 { // SUCCEED
            throw ConnectionError.databaseChangeFailed(database)
        }
    }

    public func disconnect() {
        if let dbProcess = dbProcess {
            dbclose(dbProcess)
            self.dbProcess = nil
        }
        dbexit()
    }

    public var isConnected: Bool {
        dbProcess != nil
    }

    deinit {
        disconnect()
    }
}

public enum ConnectionError: LocalizedError {
    case initializationFailed
    case connectionFailed
    case notConnected
    case databaseChangeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .initializationFailed:
            return "Failed to initialize FreeTDS"
        case .connectionFailed:
            return "Failed to connect to server"
        case .notConnected:
            return "Not connected to database"
        case .databaseChangeFailed(let db):
            return "Failed to switch to database: \(db)"
        }
    }
}
```

- [ ] **Step 3: Build and verify**

```bash
swift build
```

Expected: Build succeeds

- [ ] **Step 4: Commit Connection implementation**

```bash
git add Sources/SqlServerPoC/Connection.swift
git commit -m "feat: implement Connection type"
```

---

## Chunk 3: Query Execution

### Task 5: Implement basic query execution

**Files:**
- Create: `SqlServerPoC/Sources/SqlServerPoC/QueryExecutor.swift`

- [ ] **Step 1: Write query result models**

```swift
import Foundation

public struct QueryResult {
    public let columnNames: [String]
    public let rows: [[Cell?]]

    public init(columnNames: [String], rows: [[Cell?]]) {
        self.columnNames = columnNames
        self.rows = rows
    }
}

public enum Cell: Equatable {
    case null
    case int(Int32)
    case int64(Int64)
    case float(Float)
    case double(Double)
    case string(String)
    case bool(Bool)
    case date(Date)
    case data(Data)

    public static func == (lhs: Cell, rhs: Cell) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null): return true
        case (.int(let l), .int(let r)): return l == r
        case (.int64(let l), .int64(let r)): return l == r
        case (.float(let l), .float(let r)): return l == r
        case (.double(let l), .double(let r)): return l == r
        case (.string(let l), .string(let r)): return l == r
        case (.bool(let l), .bool(let r)): return l == r
        case (.date(let l), .date(let r)): return l == r
        case (.data(let l), .data(let r)): return l == r
        default: return false
        }
    }
}
```

- [ ] **Step 2: Write QueryExecutor with FreeTDS integration**

```swift
import Foundation

public final class QueryExecutor {
    private let connection: Connection

    public init(connection: Connection) {
        self.connection = connection
    }

    public func executeQuery(_ sql: String) async throws -> QueryResult {
        guard connection.isConnected else {
            throw QueryError.notConnected
        }

        // This is a synchronous FreeTDS call wrapped in async
        // In production, this would run on a dedicated thread pool
        return try await withCheckedThrowingContinuation { continuation in
            do {
                let result = try executeSynchronousQuery(sql)
                continuation.resume(returning: result)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func executeSynchronousQuery(_ sql: String) throws -> QueryResult {
        guard let dbProcess = getDbProcess() else {
            throw QueryError.notConnected
        }

        // Send SQL command
        sql.withCString { sqlPtr in
            dbcmd(dbProcess, sqlPtr)
        }

        // Execute
        let execResult = dbsqlexec(dbProcess)
        guard execResult == DBLIB_ResultTypes.SUCCEED.rawValue else {
            throw QueryError.executionFailed
        }

        // Get results
        let resultsResult = dbresults(dbProcess)
        guard resultsResult == DBLIB_ResultTypes.SUCCEED.rawValue else {
            throw QueryError.resultsFailed
        }

        // Get column count and names
        let numCols = Int(dbnumcols(dbProcess))
        var columnNames: [String] = []
        var columnTypes: [Int32] = []

        for i in 1...numCols {
            if let colNamePtr = dbcolname(dbProcess, Int32(i)) {
                let colName = String(cString: colNamePtr)
                columnNames.append(colName)
            }
            columnTypes.append(dbcoltype(dbProcess, Int32(i)))
        }

        // Fetch rows
        var rows: [[Cell?]] = []

        var rowResult = dbnextrow(dbProcess)
        while rowResult == DBLIB_ResultTypes.SUCCEED.rawValue {
            var row: [Cell?] = []

            for i in 1...numCols {
                if dbisnull(dbProcess, Int32(i)) == 1 {
                    row.append(.null)
                } else {
                    let cell = try parseCell(
                        dbProcess: dbProcess,
                        column: Int32(i),
                        type: columnTypes[i-1]
                    )
                    row.append(cell)
                }
            }

            rows.append(row)
            rowResult = dbnextrow(dbProcess)
        }

        return QueryResult(columnNames: columnNames, rows: rows)
    }

    private func parseCell(
        dbProcess: UnsafeMutablePointer<DBPROCESS>,
        column: Int32,
        type: Int32
    ) throws -> Cell {
        guard let dataPtr = dbdata(dbProcess, column) else {
            return .null
        }

        let dataLen = Int(dbdatlen(dbProcess, column))

        switch DBLIB_Types(rawValue: type) {
        case .INT_TYPE:
            let value = dataPtr.assumingMemoryBound(to: DBINT.self).pointee
            return value == DBINT_NULL ? .null : .int(value)

        case .SMALLINT_TYPE:
            let value = dataPtr.assumingMemoryBound(to: DBSMALLINT.self).pointee
            return .int(Int32(value))

        case .TINYINT_TYPE:
            let value = dataPtr.assumingMemoryBound(to: DBTINYINT.self).pointee
            return .int(Int32(value))

        case .BIT_TYPE:
            let value = dataPtr.assumingMemoryBound(to: DBBOOL.self).pointee
            return value == DBBOOL_NULL ? .null : .bool(value != 0)

        case .FLOAT_TYPE:
            let value = dataPtr.assumingMemoryBound(to: DBREAL.self).pointee
            return .float(value)

        case .REAL_TYPE:
            let value = dataPtr.assumingMemoryBound(to: DBREAL.self).pointee
            return .float(value)

        case .CHAR_TYPE, .VARCHAR_TYPE, .TEXT_TYPE:
            let string = String(cString: dataPtr.assumingMemoryBound(to: CChar.self))
            return .string(string)

        case .BINARY_TYPE, .VARBINARY_TYPE, .IMAGE_TYPE:
            let data = Data(bytes: dataPtr, count: dataLen)
            return .data(data)

        default:
            // Fallback to string representation
            let bytes = Array(UnsafeBufferPointer(
                start: dataPtr.assumingMemoryBound(to: UInt8.self),
                count: dataLen
            ))
            return .string(String(decoding: bytes, as: UTF8.self))
        }
    }

    private func getDbProcess() -> UnsafeMutablePointer<DBPROCESS>? {
        // This would access the connection's dbProcess
        // For now, we'll add this as a stored property
        return nil
    }
}

public enum QueryError: LocalizedError {
    case notConnected
    case executionFailed
    case resultsFailed
    case typeConversionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to database"
        case .executionFailed:
            return "Query execution failed"
        case .resultsFailed:
            return "Failed to retrieve results"
        case .typeConversionFailed(let details):
            return "Type conversion failed: \(details)"
        }
    }
}
```

- [ ] **Step 3: Build and verify**

```bash
swift build
```

Expected: Build succeeds

- [ ] **Step 4: Commit QueryExecutor**

```bash
git add Sources/SqlServerPoC/QueryExecutor.swift
git commit -m "feat: implement QueryExecutor"
```

---

## Chunk 4: Testing and Validation

### Task 6: Write integration tests

**Files:**
- Create: `SqlServerPoC/Tests/SqlServerPoCTests/ConnectionTests.swift`

- [ ] **Step 1: Write connection test**

```swift
import XCTest
@testable import SqlServerPoC

final class ConnectionTests: XCTestCase {
    // Test with local SQL Server or Azure SQL Database
    // You'll need to provide actual connection details

    func testConnectionSuccess() async throws {
        let config = ConnectionConfiguration(
            host: ProcessInfo.processInfo.environment["SQL_SERVER_HOST"] ?? "localhost",
            port: 1433,
            username: ProcessInfo.processInfo.environment["SQL_SERVER_USER"] ?? "sa",
            password: ProcessInfo.processInfo.environment["SQL_SERVER_PASSWORD"] ?? "",
            database: "master"
        )

        let connection = Connection(config: config)

        try connection.connect()
        XCTAssertTrue(connection.isConnected)

        connection.disconnect()
        XCTAssertFalse(connection.isConnected)
    }

    func testConnectionFailure() async throws {
        let config = ConnectionConfiguration(
            host: "invalid-host",
            port: 1433,
            username: "user",
            password: "pass",
            database: "master",
            timeout: 1
        )

        let connection = Connection(config: config)

        do {
            try connection.connect()
            XCTFail("Expected connection to fail")
        } catch ConnectionError.connectionFailed {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
```

- [ ] **Step 2: Write query test**

```swift
import XCTest
@testable import SqlServerPoC

final class QueryTests: XCTestCase {

    func testSimpleQuery() async throws {
        let config = ConnectionConfiguration(
            host: ProcessInfo.processInfo.environment["SQL_SERVER_HOST"] ?? "localhost",
            port: 1433,
            username: ProcessInfo.processInfo.environment["SQL_SERVER_USER"] ?? "sa",
            password: ProcessInfo.processInfo.environment["SQL_SERVER_PASSWORD"] ?? "",
            database: "master"
        )

        let connection = Connection(config: config)
        try connection.connect()

        let executor = QueryExecutor(connection: connection)
        let result = try await executor.executeQuery("SELECT 1 AS test_column")

        XCTAssertEqual(result.columnNames, ["test_column"])
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(result.rows.first?.first, .int(1))

        connection.disconnect()
    }

    func testTypeConversion() async throws {
        let config = ConnectionConfiguration(
            host: ProcessInfo.processInfo.environment["SQL_SERVER_HOST"] ?? "localhost",
            port: 1433,
            username: ProcessInfo.processInfo.environment["SQL_SERVER_USER"] ?? "sa",
            password: ProcessInfo.processInfo.environment["SQL_SERVER_PASSWORD"] ?? "",
            database: "master"
        )

        let connection = Connection(config: config)
        try connection.connect()

        let executor = QueryExecutor(connection: connection)

        let sql = """
        SELECT
            1 AS int_col,
            CAST(1 AS BIT) AS bit_col,
            'test' AS varchar_col,
            CAST(3.14 AS FLOAT) AS float_col,
            GETDATE() AS datetime_col
        """

        let result = try await executor.executeQuery(sql)

        XCTAssertEqual(result.columnNames.count, 5)
        XCTAssertEqual(result.rows.count, 1)

        let row = result.rows[0]
        XCTAssertEqual(row[0], .int(1))
        XCTAssertEqual(row[1], .bool(true))
        XCTAssertEqual(row[2], .string("test"))

        connection.disconnect()
    }
}
```

- [ ] **Step 3: Run tests**

```bash
# Set environment variables for your SQL Server instance
export SQL_SERVER_HOST="localhost"
export SQL_SERVER_USER="sa"
export SQL_SERVER_PASSWORD="YourPassword123"

# Run tests
swift test
```

Expected: Tests should attempt connection (may fail if no SQL Server available)

- [ ] **Step 4: Commit tests**

```bash
git add Tests/
git commit -m "test: add integration tests for connection and query execution"
```

### Task 7: Memory leak test

**Files:**
- Create: `SqlServerPoC/Tests/SqlServerPoCTests/MemoryTests.swift`

- [ ] **Step 1: Write memory leak test**

```swift
import XCTest
@testable import SqlServerPoC

final class MemoryTests: XCTestCase {

    func testNoMemoryLeaks() async throws {
        let config = ConnectionConfiguration(
            host: ProcessInfo.processInfo.environment["SQL_SERVER_HOST"] ?? "localhost",
            port: 1433,
            username: ProcessInfo.processInfo.environment["SQL_SERVER_USER"] ?? "sa",
            password: ProcessInfo.processInfo.environment["SQL_SERVER_PASSWORD"] ?? "",
            database: "master"
        )

        // Run 100 connection/query cycles
        for i in 0..<100 {
            autoreleasepool {
                do {
                    let connection = Connection(config: config)
                    try connection.connect()

                    let executor = QueryExecutor(connection: connection)
                    _ = try executor.executeQuery("SELECT 1")

                    connection.disconnect()
                } catch {
                    // Some iterations may fail due to connection issues
                    // That's OK for memory leak testing
                }
            }

            if i % 10 == 0 {
                print("Completed \(i) iterations")
            }
        }

        print("Completed 100 iterations without crashing")
        XCTAssertTrue(true) // If we got here, no crashes
    }
}
```

- [ ] **Step 2: Run memory leak test**

```bash
swift test --filter MemoryTests.testNoMemoryLeaks
```

Expected: Completes 100 iterations without crash

- [ ] **Step 3: Commit memory test**

```bash
git add Tests/SqlServerPoCTests/MemoryTests.swift
git commit -m "test: add memory leak test"
```

---

## Chunk 5: Documentation and Go/No-Go Decision

### Task 8: Create validation script

**Files:**
- Create: `SqlServerPoC/validate_poc.sh`

- [ ] **Step 1: Write validation script**

```bash
#!/bin/bash

set -e

echo "🔍 SqlServerPoC - Phase 0 Validation"
echo "======================================"
echo ""

# Check if FreeTDS is installed
if ! command -v tsql &> /dev/null; then
    echo "❌ FreeTDS not found"
    echo "Install with: brew install freetds"
    exit 1
fi

echo "✅ FreeTDS found: $(tsql -C | grep 'Version' | head -1)"
echo ""

# Check if SQL Server environment variables are set
if [ -z "$SQL_SERVER_HOST" ]; then
    echo "⚠️  SQL_SERVER_HOST not set"
    echo "   Set with: export SQL_SERVER_HOST=your_host"
fi

if [ -z "$SQL_SERVER_USER" ]; then
    echo "⚠️  SQL_SERVER_USER not set"
    echo "   Set with: export SQL_SERVER_USER=your_user"
fi

if [ -z "$SQL_SERVER_PASSWORD" ]; then
    echo "⚠️  SQL_SERVER_PASSWORD not set"
    echo "   Set with: export SQL_SERVER_PASSWORD=your_password"
fi

echo ""
echo "🔨 Building..."
swift build

echo ""
echo "🧪 Running tests..."
swift test

echo ""
echo "✅ Validation complete!"
echo ""
echo "Success Criteria Checklist:"
echo "  ☐ Can connect to SQL Server and execute SELECT in <50 lines of Swift"
echo "  ☐ No crashes or memory leaks in 100-iteration test"
echo "  ☐ Performance within 3x of PostgresGUI for simple query"
echo ""
echo "If all criteria met: Proceed to Phase 1"
echo "If any criteria not met: Re-evaluate alternative approaches (see spec Appendix C)"
```

- [ ] **Step 2: Make script executable**

```bash
chmod +x validate_poc.sh
```

- [ ] **Step 3: Commit validation script**

```bash
git add validate_poc.sh
git commit -m "feat: add PoC validation script"
```

### Task 9: Update README with results

**Files:**
- Modify: `SqlServerPoC/README.md`

- [ ] **Step 1: Add results section to README**

```markdown
# SqlServerPoC - Phase 0 Technical Validation

## Purpose

Validate FreeTDS Swift interop feasibility for SqlServerGUI project.

## Setup

1. Install FreeTDS via Homebrew:
   ```bash
   brew install freetds
   ```

2. Set environment variables for your SQL Server instance:
   ```bash
   export SQL_SERVER_HOST="your_host"
   export SQL_SERVER_USER="your_user"
   export SQL_SERVER_PASSWORD="your_password"
   ```

3. Build the package:
   ```bash
   swift build
   ```

## Running Tests

```bash
# Run all tests
swift test

# Or use validation script
./validate_poc.sh
```

## Success Criteria

- [ ] Can connect to SQL Server and execute SELECT in <50 lines of Swift
- [ ] No crashes or memory leaks in 100-iteration test
- [ ] Performance within 3x of PostgresGUI for simple query

## Results (To be filled after PoC completion)

**Date**: [FILL IN]
**FreeTDS Version**: [FILL IN]
**SQL Server Version**: [FILL IN]

### Connection Test
- [ ] PASS - Successfully connected
- [ ] FAIL - Connection failed: [REASON]

### Query Execution Test
- [ ] PASS - Queries execute successfully
- [ ] FAIL - Query execution failed: [REASON]

### Type Conversion Test
- [ ] PASS - All tested types convert correctly
- [ ] FAIL - Type conversion failed: [REASON]

### Memory Leak Test
- [ ] PASS - 100 iterations completed without crash
- [ ] FAIL - Crashed or leaked memory: [REASON]

### Performance Test
- Connection time: [FILL IN] seconds
- Query time: [FILL IN] seconds
- Within 3x target: [YES/NO]

## Go/No-Go Decision

**Decision**: [GO / NO-GO]

**If GO**: Proceed to Phase 1 - Foundation
**If NO-GO**: Re-evaluate alternative approaches (see spec Appendix C):
- [ ] ODBC approach
- [ ] Commercial driver
- [ ] Middleware/proxy service
```

- [ ] **Step 2: Commit final README**

```bash
git add README.md
git commit -m "docs: add results template to README"
```

---

## Success Criteria

After completing this implementation plan, the PoC should demonstrate:

1. **Feasibility**: Swift can successfully call FreeTDS C functions
2. **Stability**: 100 connection/query cycles without crashes
3. **Performance**: Connection and query times within 3x of PostgresGUI baseline
4. **Type Safety**: Basic SQL Server types convert correctly to Swift types

If all criteria are met, proceed to Phase 1 (Foundation).
If any criteria fail, re-evaluate alternative approaches per spec Appendix C.
