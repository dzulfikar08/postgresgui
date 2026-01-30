//
//  TabState.swift
//  PostgresGUI
//
//  Created by ghazi on 12/20/25.
//

import Foundation
import SwiftData

@Model
final class TabState: Identifiable {
    var id: UUID
    var connectionId: UUID?
    var databaseName: String?
    var queryText: String
    var savedQueryId: UUID?
    var isActive: Bool
    var order: Int
    var createdAt: Date
    var lastAccessedAt: Date

    // Selected table state
    var selectedTableSchema: String?
    var selectedTableName: String?

    // Schema filter (for sidebar filtering)
    var selectedSchemaFilter: String?

    // Cached query results
    var cachedResultsData: Data?
    var cachedColumnNames: [String]?

    init(
        id: UUID = UUID(),
        connectionId: UUID? = nil,
        databaseName: String? = nil,
        queryText: String = "",
        savedQueryId: UUID? = nil,
        isActive: Bool = false,
        order: Int = 0,
        createdAt: Date = Date(),
        lastAccessedAt: Date = Date(),
        selectedTableSchema: String? = nil,
        selectedTableName: String? = nil,
        selectedSchemaFilter: String? = nil,
        cachedResultsData: Data? = nil,
        cachedColumnNames: [String]? = nil
    ) {
        self.id = id
        self.connectionId = connectionId
        self.databaseName = databaseName
        self.queryText = queryText
        self.savedQueryId = savedQueryId
        self.isActive = isActive
        self.order = order
        self.createdAt = createdAt
        self.lastAccessedAt = lastAccessedAt
        self.selectedTableSchema = selectedTableSchema
        self.selectedTableName = selectedTableName
        self.selectedSchemaFilter = selectedSchemaFilter
        self.cachedResultsData = cachedResultsData
        self.cachedColumnNames = cachedColumnNames
    }

    // MARK: - Results Encoding/Decoding

    /// Decode cached results from Data
    var cachedResults: [TableRow]? {
        guard let data = cachedResultsData else { return nil }
        do {
            return try JSONDecoder().decode([TableRow].self, from: data)
        } catch {
            return nil
        }
    }

    /// Encode and store results
    func setCachedResults(_ results: [TableRow]?, columnNames: [String]?) {
        if let results = results {
            cachedResultsData = try? JSONEncoder().encode(results)
        } else {
            cachedResultsData = nil
        }
        cachedColumnNames = columnNames
    }

    /// Clear cached results
    func clearCachedResults() {
        cachedResultsData = nil
        cachedColumnNames = nil
    }
}
