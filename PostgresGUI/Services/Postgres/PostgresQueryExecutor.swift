//
//  PostgresQueryExecutor.swift
//  PostgresGUI
//
//  PostgresNIO-specific implementation of QueryExecutorProtocol.
//  Executes queries and delegates result mapping to ResultMapperProtocol.
//

import Foundation
import PostgresNIO
import Logging

/// PostgresNIO implementation of QueryExecutorProtocol
struct PostgresQueryExecutor: QueryExecutorProtocol {

    private let logger = Logger.debugLogger(label: "com.postgresgui.query")
    private let resultMapper: ResultMapperProtocol

    // MARK: - Initialization

    init(resultMapper: ResultMapperProtocol = PostgresResultMapper()) {
        self.resultMapper = resultMapper
    }

    // MARK: - Database Operations

    func fetchDatabases(connection: DatabaseConnectionProtocol) async throws -> [DatabaseInfo] {
        let sql = """
        SELECT datname
        FROM pg_database
        WHERE datistemplate = false
        ORDER BY datname
        """

        logger.debug("Fetching databases")

        let rows = try await connection.executeQuery(sql)
        var databases: [DatabaseInfo] = []

        for try await row in rows {
            guard let dbRow = row as? any DatabaseRow else {
                throw DatabaseError.unknownError("Expected DatabaseRow")
            }
            let db = try resultMapper.mapToDatabaseInfo(dbRow)
            databases.append(db)
        }

        logger.info("Fetched \(databases.count) databases")
        return databases
    }

    func createDatabase(connection: DatabaseConnectionProtocol, name: String) async throws {
        let sanitizedName = sanitizeIdentifier(name)
        let sql = "CREATE DATABASE \(sanitizedName)"

        logger.info("Creating database: \(sanitizedName)")

        _ = try await connection.executeQuery(sql)
        logger.info("Database created successfully")
    }

    func dropDatabase(connection: DatabaseConnectionProtocol, name: String) async throws {
        let sanitizedName = sanitizeIdentifier(name)
        let sql = "DROP DATABASE \(sanitizedName)"

        logger.info("Dropping database: \(sanitizedName)")

        _ = try await connection.executeQuery(sql)
        logger.info("Database dropped successfully")
    }

    // MARK: - Table Operations

    func fetchTables(connection: DatabaseConnectionProtocol) async throws -> [TableInfo] {
        let sql = """
        SELECT schemaname, tablename, 'regular' as tabletype
        FROM pg_tables
        WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
        UNION ALL
        SELECT foreign_table_schema, foreign_table_name, 'foreign' as tabletype
        FROM information_schema.foreign_tables
        ORDER BY schemaname, tablename
        """

        logger.debug("Fetching tables")

        let rows = try await connection.executeQuery(sql)
        var tables: [TableInfo] = []

        for try await row in rows {
            guard let dbRow = row as? any DatabaseRow else {
                throw DatabaseError.unknownError("Expected DatabaseRow")
            }
            let table = try resultMapper.mapToTableInfo(dbRow)
            tables.append(table)
        }

        logger.info("Fetched \(tables.count) tables")
        return tables
    }

    func fetchSchemas(connection: DatabaseConnectionProtocol) async throws -> [String] {
        let sql = """
        SELECT DISTINCT schemaname
        FROM pg_tables
        WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
        UNION
        SELECT DISTINCT foreign_table_schema
        FROM information_schema.foreign_tables
        ORDER BY schemaname
        """

        logger.debug("Fetching schemas")

        let rows = try await connection.executeQuery(sql)
        var schemas: [String] = []

        for try await row in rows {
            guard let postgresRow = row as? PostgresDatabaseRow else {
                throw DatabaseError.unknownError("Expected PostgresDatabaseRow")
            }
            let schemaName = try postgresRow.row.decode(String.self)
            schemas.append(schemaName)
        }

        logger.info("Fetched \(schemas.count) schemas")
        return schemas
    }

    func fetchTableData(
        connection: DatabaseConnectionProtocol,
        schema: String,
        table: String,
        limit: Int,
        offset: Int
    ) async throws -> [TableRow] {
        let qualifiedTable = "\(sanitizeIdentifier(schema)).\(sanitizeIdentifier(table))"
        let sql = "SELECT * FROM \(qualifiedTable) LIMIT \(limit) OFFSET \(offset)"

        logger.debug("Fetching table data: \(qualifiedTable), limit: \(limit), offset: \(offset)")

        let rows = try await connection.executeQuery(sql)
        let tableRows = try await resultMapper.mapRowsToTableRows(rows)

        logger.info("Fetched \(tableRows.count) rows from \(qualifiedTable)")
        return tableRows
    }

    func dropTable(
        connection: DatabaseConnectionProtocol,
        schema: String,
        table: String
    ) async throws {
        let qualifiedTable = "\(sanitizeIdentifier(schema)).\(sanitizeIdentifier(table))"
        let sql = "DROP TABLE \(qualifiedTable)"

        logger.info("Dropping table: \(qualifiedTable)")

        _ = try await connection.executeQuery(sql)
        logger.info("Table dropped successfully")
    }

    func truncateTable(
        connection: DatabaseConnectionProtocol,
        schema: String,
        table: String
    ) async throws {
        let qualifiedTable = "\(sanitizeIdentifier(schema)).\(sanitizeIdentifier(table))"
        let sql = "TRUNCATE TABLE \(qualifiedTable)"

        logger.info("Truncating table: \(qualifiedTable)")

        _ = try await connection.executeQuery(sql)
        logger.info("Table truncated successfully")
    }

    func generateDDL(
        connection: DatabaseConnectionProtocol,
        schema: String,
        table: String
    ) async throws -> String {
        logger.info("Generating DDL for \(schema).\(table)")

        // Fetch column information with more details
        let columnsSql = """
        SELECT
            column_name,
            data_type,
            character_maximum_length,
            numeric_precision,
            numeric_scale,
            column_default,
            is_nullable,
            udt_name,
            is_identity,
            identity_generation
        FROM information_schema.columns
        WHERE table_schema = '\(schema)' AND table_name = '\(table)'
        ORDER BY ordinal_position
        """

        let columnRows = try await connection.executeQuery(columnsSql)
        var columns: [(name: String, definition: String)] = []

        for try await row in columnRows {
            guard let dbRow = row as? any DatabaseRow else {
                throw DatabaseError.unknownError("Expected DatabaseRow")
            }

            let columnName = try dbRow.decode(String.self, column: "column_name")
            let dataType = try dbRow.decode(String.self, column: "data_type")
            let isNullable = try dbRow.decode(String.self, column: "is_nullable")
            let columnDefault = try dbRow.decode(String?.self, column: "column_default")
            let charMaxLength = try dbRow.decode(Int?.self, column: "character_maximum_length")
            let numericPrecision = try dbRow.decode(Int?.self, column: "numeric_precision")
            let numericScale = try dbRow.decode(Int?.self, column: "numeric_scale")
            let udtName = try dbRow.decode(String.self, column: "udt_name")
            let isIdentity = try dbRow.decode(String?.self, column: "is_identity")
            let identityGeneration = try dbRow.decode(String?.self, column: "identity_generation")

            var typeDef = buildTypeDefinition(
                dataType: dataType,
                udtName: udtName,
                charMaxLength: charMaxLength,
                numericPrecision: numericPrecision,
                numericScale: numericScale
            )

            // Handle identity columns
            if isIdentity == "YES" {
                if identityGeneration == "ALWAYS" {
                    typeDef += " GENERATED ALWAYS AS IDENTITY"
                } else if identityGeneration == "BY DEFAULT" {
                    typeDef += " GENERATED BY DEFAULT AS IDENTITY"
                }
            } else if let defaultVal = columnDefault, !defaultVal.isEmpty {
                typeDef += " DEFAULT \(defaultVal)"
            }

            if isNullable == "NO" {
                typeDef += " NOT NULL"
            }

            columns.append((name: sanitizeIdentifier(columnName), definition: typeDef))
        }

        // Fetch constraints
        let constraintsSql = """
        SELECT
            c.conname AS constraint_name,
            c.contype AS constraint_type,
            pg_get_constraintdef(c.oid) AS definition
        FROM pg_constraint c
        JOIN pg_class t ON c.conrelid = t.oid
        JOIN pg_namespace n ON t.relnamespace = n.oid
        WHERE n.nspname = '\(schema)' AND t.relname = '\(table)'
        ORDER BY c.contype DESC, c.conname
        """

        let constraintRows = try await connection.executeQuery(constraintsSql)
        var constraints: [String] = []

        for try await row in constraintRows {
            guard let dbRow = row as? any DatabaseRow else {
                throw DatabaseError.unknownError("Expected DatabaseRow")
            }

            let constraintName = try dbRow.decode(String.self, column: "constraint_name")
            let definition = try dbRow.decode(String.self, column: "definition")

            constraints.append("CONSTRAINT \(sanitizeIdentifier(constraintName)) \(definition)")
        }

        // Build CREATE TABLE statement
        let qualifiedTable = "\(sanitizeIdentifier(schema)).\(sanitizeIdentifier(table))"
        var ddl = "CREATE TABLE \(qualifiedTable) (\n"

        let columnDefs = columns.map { "    \($0.name) \($0.definition)" }
        var allDefs = columnDefs

        if !constraints.isEmpty {
            allDefs.append(contentsOf: constraints.map { "    \($0)" })
        }

        ddl += allDefs.joined(separator: ",\n")
        ddl += "\n);"

        logger.info("DDL generated successfully for \(schema).\(table)")
        return ddl
    }

    /// Build the type definition string for a column
    private func buildTypeDefinition(
        dataType: String,
        udtName: String,
        charMaxLength: Int?,
        numericPrecision: Int?,
        numericScale: Int?
    ) -> String {
        // Use udt_name for array types and user-defined types
        if udtName.hasPrefix("_") {
            // Array type - remove underscore prefix and add []
            let baseType = String(udtName.dropFirst())
            return "\(baseType)[]"
        }

        switch dataType.lowercased() {
        case "character varying":
            if let length = charMaxLength {
                return "VARCHAR(\(length))"
            }
            return "VARCHAR"
        case "character":
            if let length = charMaxLength {
                return "CHAR(\(length))"
            }
            return "CHAR"
        case "numeric":
            if let precision = numericPrecision {
                if let scale = numericScale, scale > 0 {
                    return "NUMERIC(\(precision), \(scale))"
                }
                return "NUMERIC(\(precision))"
            }
            return "NUMERIC"
        case "array":
            return "\(udtName)"
        case "user-defined":
            return udtName
        default:
            return dataType.uppercased()
        }
    }

    // MARK: - Column Metadata

    func fetchColumns(
        connection: DatabaseConnectionProtocol,
        schema: String,
        table: String
    ) async throws -> [ColumnInfo] {
        let sql = """
        SELECT
            column_name,
            data_type,
            is_nullable,
            column_default
        FROM information_schema.columns
        WHERE table_schema = '\(schema)' AND table_name = '\(table)'
        ORDER BY ordinal_position
        """

        logger.debug("Fetching columns for \(schema).\(table)")

        let rows = try await connection.executeQuery(sql)
        var columns: [ColumnInfo] = []

        for try await row in rows {
            guard let dbRow = row as? any DatabaseRow else {
                throw DatabaseError.unknownError("Expected DatabaseRow")
            }
            let column = try resultMapper.mapToColumnInfo(dbRow)
            columns.append(column)
        }

        logger.info("Fetched \(columns.count) columns for \(schema).\(table)")
        return columns
    }

    func fetchPrimaryKeys(
        connection: DatabaseConnectionProtocol,
        schema: String,
        table: String
    ) async throws -> [String] {
        let sql = """
        SELECT a.attname
        FROM pg_index i
        JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
        WHERE i.indrelid = ('\(schema).\(table)')::regclass AND i.indisprimary
        """

        logger.debug("Fetching primary keys for \(schema).\(table)")

        let rows = try await connection.executeQuery(sql)
        var primaryKeys: [String] = []

        for try await row in rows {
            guard let dbRow = row as? any DatabaseRow else {
                throw DatabaseError.unknownError("Expected DatabaseRow")
            }
            // Use the protocol's decode method via the "attname" column
            let pkColumn = try dbRow.decode(String.self, column: "attname")
            primaryKeys.append(pkColumn)
        }

        logger.info("Found \(primaryKeys.count) primary key columns for \(schema).\(table)")
        return primaryKeys
    }

    // MARK: - Query Execution

    func executeQuery(
        connection: DatabaseConnectionProtocol,
        sql: String
    ) async throws -> ([TableRow], [String]) {
        logger.info("Executing query: \(sql.prefix(100))...")

        let startTime = Date()

        let rows = try await connection.executeQuery(sql)

        var tableRows: [TableRow] = []
        var columnNames: [String] = []

        for try await row in rows {
            guard let dbRow = row as? any DatabaseRow else {
                throw DatabaseError.unknownError("Expected DatabaseRow")
            }
            if columnNames.isEmpty {
                columnNames = dbRow.columnNames
            }

            let tableRow = try resultMapper.mapRowToTableRow(dbRow)
            tableRows.append(tableRow)
        }

        let executionTime = Date().timeIntervalSince(startTime)
        logger.info("Query executed in \(String(format: "%.3f", executionTime))s, returned \(tableRows.count) rows")

        return (tableRows, columnNames)
    }

    // MARK: - Row Operations

    func updateRow(
        connection: DatabaseConnectionProtocol,
        schema: String,
        table: String,
        primaryKeyColumns: [String],
        originalRow: TableRow,
        updatedValues: [String: RowEditValue]
    ) async throws {
        guard !primaryKeyColumns.isEmpty else {
            throw DatabaseError.noPrimaryKey
        }

        let qualifiedTable = "\(sanitizeIdentifier(schema)).\(sanitizeIdentifier(table))"

        // Exclude primary key columns from SET clause - they cannot be updated
        // (especially important for GENERATED ALWAYS identity columns)
        let pkSet = Set(primaryKeyColumns)

        var setClauses: [String] = []
        for (column, value) in updatedValues where !pkSet.contains(column) {
            switch value {
            case .value(let val):
                setClauses.append("\(sanitizeIdentifier(column)) = '\(val.replacingOccurrences(of: "'", with: "''"))'")
            case .null:
                setClauses.append("\(sanitizeIdentifier(column)) = NULL")
            }
        }

        // Ensure we have at least one column to update
        guard !setClauses.isEmpty else {
            logger.info("No columns to update (all columns are primary keys)")
            return
        }

        var whereClauses: [String] = []
        for pkColumn in primaryKeyColumns {
            guard let pkValue = originalRow.values[pkColumn] else {
                throw DatabaseError.missingPrimaryKeyValue(column: pkColumn)
            }

            if let val = pkValue {
                whereClauses.append("\(sanitizeIdentifier(pkColumn)) = '\(val.replacingOccurrences(of: "'", with: "''"))'")
            } else {
                whereClauses.append("\(sanitizeIdentifier(pkColumn)) IS NULL")
            }
        }

        let sql = """
        UPDATE \(qualifiedTable)
        SET \(setClauses.joined(separator: ", "))
        WHERE \(whereClauses.joined(separator: " AND "))
        """

        logger.info("Updating row in \(qualifiedTable)")
        logger.debug("SQL: \(sql)")

        _ = try await connection.executeQuery(sql)
        logger.info("Row updated successfully")
    }

    func deleteRows(
        connection: DatabaseConnectionProtocol,
        schema: String,
        table: String,
        primaryKeyColumns: [String],
        rows: [TableRow]
    ) async throws {
        guard !primaryKeyColumns.isEmpty else {
            throw DatabaseError.noPrimaryKey
        }

        let qualifiedTable = "\(sanitizeIdentifier(schema)).\(sanitizeIdentifier(table))"

        for row in rows {
            var whereClauses: [String] = []

            for pkColumn in primaryKeyColumns {
                guard let pkValue = row.values[pkColumn] else {
                    throw DatabaseError.missingPrimaryKeyValue(column: pkColumn)
                }

                if let val = pkValue {
                    whereClauses.append("\(sanitizeIdentifier(pkColumn)) = '\(val.replacingOccurrences(of: "'", with: "''"))'")
                } else {
                    whereClauses.append("\(sanitizeIdentifier(pkColumn)) IS NULL")
                }
            }

            let sql = """
            DELETE FROM \(qualifiedTable)
            WHERE \(whereClauses.joined(separator: " AND "))
            """

            logger.debug("Deleting row from \(qualifiedTable)")
            _ = try await connection.executeQuery(sql)
        }

        logger.info("Deleted \(rows.count) row(s) from \(qualifiedTable)")
    }

    // MARK: - Helpers

    /// Sanitize SQL identifier (table name, column name, etc.)
    private func sanitizeIdentifier(_ identifier: String) -> String {
        let escaped = identifier.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
