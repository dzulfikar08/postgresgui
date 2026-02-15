//
//  TableService.swift
//  PostgresGUI
//
//  Created by ghazi on 12/17/25.
//

import Foundation
import Logging

/// Service for table operations
@MainActor
class TableService: TableServiceProtocol {
    private let connectionManager: ConnectionManagerProtocol
    private let queryExecutor: QueryExecutorProtocol
    private let logger = Logger.debugLogger(label: "com.postgresgui.tableservice")

    init(connectionManager: ConnectionManagerProtocol, queryExecutor: QueryExecutorProtocol) {
        self.connectionManager = connectionManager
        self.queryExecutor = queryExecutor
    }

    /// Fetch list of tables in the connected database
    func fetchTables(database: String) async throws -> [TableInfo] {
        logger.debug("Fetching tables for database: \(database)")
        let queryExecutor = self.queryExecutor

        return try await connectionManager.withConnection { conn in
            try await queryExecutor.fetchTables(connection: conn)
        }
    }

    /// Fetch list of schemas in the connected database
    func fetchSchemas(database: String) async throws -> [String] {
        logger.debug("Fetching schemas for database: \(database)")
        let queryExecutor = self.queryExecutor

        return try await connectionManager.withConnection { conn in
            try await queryExecutor.fetchSchemas(connection: conn)
        }
    }

    /// Fetch table data with pagination
    func fetchTableData(
        schema: String,
        table: String,
        offset: Int,
        limit: Int
    ) async throws -> [TableRow] {
        logger.debug("Fetching table data: \(schema).\(table)")
        let queryExecutor = self.queryExecutor

        return try await connectionManager.withConnection { conn in
            try await queryExecutor.fetchTableData(
                connection: conn,
                schema: schema,
                table: table,
                limit: limit,
                offset: offset
            )
        }
    }

    /// Delete a table
    func deleteTable(schema: String, table: String) async throws {
        logger.info("Deleting table: \(schema).\(table)")
        let queryExecutor = self.queryExecutor

        try await connectionManager.withConnection { conn in
            try await queryExecutor.dropTable(connection: conn, schema: schema, table: table)
        }
    }

    /// Truncate a table (delete all rows)
    func truncateTable(schema: String, table: String) async throws {
        logger.info("Truncating table: \(schema).\(table)")
        let queryExecutor = self.queryExecutor

        try await connectionManager.withConnection { conn in
            try await queryExecutor.truncateTable(connection: conn, schema: schema, table: table)
        }
    }

    /// Generate DDL (CREATE TABLE statement) for a table
    func generateDDL(schema: String, table: String) async throws -> String {
        logger.debug("Generating DDL for: \(schema).\(table)")
        let queryExecutor = self.queryExecutor

        return try await connectionManager.withConnection { conn in
            try await queryExecutor.generateDDL(connection: conn, schema: schema, table: table)
        }
    }

    /// Fetch all table data (no pagination, for export)
    func fetchAllTableData(schema: String, table: String) async throws -> ([TableRow], [String]) {
        logger.debug("Fetching all data from: \(schema).\(table)")
        let queryExecutor = self.queryExecutor

        return try await connectionManager.withConnection { conn in
            // Use a sanitized SELECT * query with no limit
            let sanitizedSchema = schema.replacingOccurrences(of: "\"", with: "\"\"")
            let sanitizedTable = table.replacingOccurrences(of: "\"", with: "\"\"")
            let sql = "SELECT * FROM \"\(sanitizedSchema)\".\"\(sanitizedTable)\""
            return try await queryExecutor.executeQuery(connection: conn, sql: sql)
        }
    }
}
