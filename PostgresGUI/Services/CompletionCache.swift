//
//  CompletionCache.swift
//  PostgresGUI
//
//  Cache for database metadata used by auto-completion
//

import Foundation
import Logging

@MainActor
class CompletionCache: CompletionCacheProtocol {
    private let metadataService: MetadataServiceProtocol
    private let logger = Logger.debugLogger(label: "com.postgresgui.completioncache")

    /// Cache structure: [connectionId: [databaseId: [schema: [TableInfo]]]]
    private var cache: [String: [String: [String: [TableInfo]]]] = [:]

    /// Track loading state to prevent duplicate fetches
    private var loadingDatabases: Set<String> = []

    private let appState: AppState

    init(metadataService: MetadataServiceProtocol, appState: AppState) {
        self.metadataService = metadataService
        self.appState = appState
    }

    /// Get all tables for a database
    func getTables(forDatabase databaseId: String) -> [TableInfo]? {
        guard let connectionId = getCurrentConnectionId() else { return nil }
        return cache[connectionId]?[databaseId]?.values.flatMap { $0 }
    }

    /// Get columns for a specific table
    func getColumns(forTable tableName: String, inSchema schema: String) -> [ColumnInfo]? {
        guard let connectionId = getCurrentConnectionId() else { return nil }
        guard let databaseId = getCurrentDatabaseId() else { return nil }
        return cache[connectionId]?[databaseId]?[schema]?.first { $0.name == tableName }?.columnInfo
    }

    /// Invalidate cache for a specific database
    func invalidateDatabase(_ databaseId: String) {
        guard let connectionId = getCurrentConnectionId() else { return }
        cache[connectionId]?[databaseId] = nil
        logger.debug("Invalidated cache for database: \(databaseId)")
    }

    /// Load metadata for a database
    func loadMetadata(forDatabase databaseId: String) async throws {
        let cacheKey = makeCacheKey(databaseId: databaseId)

        guard !loadingDatabases.contains(cacheKey) else {
            logger.debug("Already loading database: \(databaseId)")
            return
        }

        loadingDatabases.insert(cacheKey)
        defer { loadingDatabases.remove(cacheKey) }

        do {
            // Fetch metadata
            let schemaMetadata = try await metadataService.fetchAllSchemaMetadata(databaseId: databaseId)

            // Store in cache
            let connectionId = getCurrentConnectionId() ?? "default"
            if cache[connectionId] == nil {
                cache[connectionId] = [:]
            }
            cache[connectionId]?[databaseId] = schemaMetadata

            logger.debug("Loaded metadata for database: \(databaseId), schemas: \(schemaMetadata.keys.count)")
        } catch {
            logger.error("Failed to load metadata for database: \(databaseId), error: \(error)")
            // Don't throw - allow app to continue with keyword-only completions
        }
    }

    // MARK: - Private Helpers

    private func getCurrentConnectionId() -> String? {
        return appState.connection.currentConnection?.id.uuidString
    }

    private func getCurrentDatabaseId() -> String? {
        return appState.connection.selectedDatabase?.id
    }

    private func makeCacheKey(databaseId: String) -> String {
        let connectionId = getCurrentConnectionId() ?? "default"
        return "\(connectionId):\(databaseId)"
    }
}
