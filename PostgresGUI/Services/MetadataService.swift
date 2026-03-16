//
//  MetadataService.swift
//  PostgresGUI
//
//  Created by ghazi on 12/17/25.
//

import Foundation
import Logging

/// Service for database metadata operations
@MainActor
class MetadataService: MetadataServiceProtocol {
    private let connectionManager: ConnectionManagerProtocol
    private let queryExecutor: QueryExecutorProtocol
    private let logger = Logger.debugLogger(label: "com.postgresgui.metadataservice")

    init(connectionManager: ConnectionManagerProtocol, queryExecutor: QueryExecutorProtocol) {
        self.connectionManager = connectionManager
        self.queryExecutor = queryExecutor
    }

    /// Fetch list of databases
    func fetchDatabases() async throws -> [DatabaseInfo] {
        logger.debug("Fetching databases")
        let queryExecutor = self.queryExecutor

        return try await connectionManager.withConnection { conn in
            try await queryExecutor.fetchDatabases(connection: conn)
        }
    }

    /// Fetch primary key columns for a table
    func fetchPrimaryKeyColumns(schema: String, table: String) async throws -> [String] {
        logger.debug("Fetching primary keys for \(schema).\(table)")
        let queryExecutor = self.queryExecutor

        return try await connectionManager.withConnection { conn in
            try await queryExecutor.fetchPrimaryKeys(connection: conn, schema: schema, table: table)
        }
    }

    /// Fetch column information for a table
    func fetchColumnInfo(schema: String, table: String) async throws -> [ColumnInfo] {
        logger.debug("Fetching column info for \(schema).\(table)")
        let queryExecutor = self.queryExecutor

        return try await connectionManager.withConnection { conn in
            try await queryExecutor.fetchColumns(connection: conn, schema: schema, table: table)
        }
    }

    /// Fetch all schema metadata for a database
    func fetchAllSchemaMetadata(databaseId: String) async throws -> [String: [TableInfo]] {
        logger.debug("Fetching all schema metadata for database: \(databaseId)")

        return try await connectionManager.withConnection { conn in
            try await self.queryExecutor.fetchAllSchemaMetadata(connection: conn)
        }
    }
}
