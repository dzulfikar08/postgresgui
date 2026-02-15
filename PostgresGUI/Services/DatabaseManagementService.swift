//
//  DatabaseManagementService.swift
//  PostgresGUI
//
//  Created by ghazi on 12/17/25.
//

import Foundation
import Logging

/// Service for database management operations
@MainActor
class DatabaseManagementService: DatabaseManagementServiceProtocol {
    private let connectionManager: ConnectionManagerProtocol
    private let queryExecutor: QueryExecutorProtocol
    private let logger = Logger.debugLogger(label: "com.postgresgui.dbmanagementservice")

    // Reference to database service to check if we're deleting the current database
    private weak var databaseService: (any DatabaseServiceProtocol)?

    init(
        connectionManager: ConnectionManagerProtocol,
        queryExecutor: QueryExecutorProtocol,
        databaseService: (any DatabaseServiceProtocol)? = nil
    ) {
        self.connectionManager = connectionManager
        self.queryExecutor = queryExecutor
        self.databaseService = databaseService
    }

    /// Create a new database
    func createDatabase(name: String) async throws {
        logger.info("Creating database: \(name)")
        let queryExecutor = self.queryExecutor

        try await connectionManager.withConnection { conn in
            try await queryExecutor.createDatabase(connection: conn, name: name)
        }
    }

    /// Delete a database
    func deleteDatabase(name: String) async throws {
        logger.info("Deleting database: \(name)")
        let queryExecutor = self.queryExecutor

        try await connectionManager.withConnection { conn in
            try await queryExecutor.dropDatabase(connection: conn, name: name)
        }

        // If we deleted the current database, disconnect
        if databaseService?.connectedDatabase == name {
            await databaseService?.disconnect()
        }
    }
}
