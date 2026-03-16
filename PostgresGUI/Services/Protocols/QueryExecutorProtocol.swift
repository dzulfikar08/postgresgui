//
//  QueryExecutorProtocol.swift
//  PostgresGUI
//
//  Abstract protocol for query execution operations
//  Allows swapping between different PostgreSQL libraries
//

import Foundation

/// Protocol defining query execution operations
/// Implementations wrap library-specific query executors
protocol QueryExecutorProtocol {
    /// Fetch all non-template databases
    func fetchDatabases(connection: DatabaseConnectionProtocol) async throws -> [DatabaseInfo]
    
    /// Create a new database
    func createDatabase(connection: DatabaseConnectionProtocol, name: String) async throws
    
    /// Drop a database
    func dropDatabase(connection: DatabaseConnectionProtocol, name: String) async throws
    
    /// Fetch all tables from user schemas
    func fetchTables(connection: DatabaseConnectionProtocol) async throws -> [TableInfo]

    /// Fetch all user schemas (excludes system schemas)
    func fetchSchemas(connection: DatabaseConnectionProtocol) async throws -> [String]
    
    /// Fetch table data with pagination
    func fetchTableData(
        connection: DatabaseConnectionProtocol,
        schema: String,
        table: String,
        limit: Int,
        offset: Int
    ) async throws -> [TableRow]
    
    /// Drop a table
    func dropTable(
        connection: DatabaseConnectionProtocol,
        schema: String,
        table: String
    ) async throws

    /// Truncate a table (delete all rows)
    func truncateTable(
        connection: DatabaseConnectionProtocol,
        schema: String,
        table: String
    ) async throws

    /// Generate DDL (CREATE TABLE statement) for a table
    func generateDDL(
        connection: DatabaseConnectionProtocol,
        schema: String,
        table: String
    ) async throws -> String
    
    /// Fetch column information for a table
    func fetchColumns(
        connection: DatabaseConnectionProtocol,
        schema: String,
        table: String
    ) async throws -> [ColumnInfo]
    
    /// Fetch primary key columns for a table
    func fetchPrimaryKeys(
        connection: DatabaseConnectionProtocol,
        schema: String,
        table: String
    ) async throws -> [String]

    /// Fetch all tables with their column information for a database
    /// - Parameter connection: Database connection
    /// - Returns: Dictionary keyed by schema name
    func fetchAllSchemaMetadata(connection: DatabaseConnectionProtocol) async throws -> [String: [TableInfo]]

    /// Execute arbitrary SQL query
    func executeQuery(
        connection: DatabaseConnectionProtocol,
        sql: String
    ) async throws -> ([TableRow], [String])
    
    /// Update a row in a table
    func updateRow(
        connection: DatabaseConnectionProtocol,
        schema: String,
        table: String,
        primaryKeyColumns: [String],
        originalRow: TableRow,
        updatedValues: [String: RowEditValue]
    ) async throws
    
    /// Delete rows from a table
    func deleteRows(
        connection: DatabaseConnectionProtocol,
        schema: String,
        table: String,
        primaryKeyColumns: [String],
        rows: [TableRow]
    ) async throws
}

