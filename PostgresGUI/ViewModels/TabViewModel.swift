//
//  TabViewModel.swift
//  PostgresGUI
//
//  In-memory view model for tabs. UI interacts with this, never with TabState directly.
//  This decouples UI operations from SwiftData persistence, preventing crashes when
//  tabs are deleted while async operations are in flight.
//
//  Created by ghazi on 1/2/26.
//

import Foundation

/// In-memory representation of a tab for UI use.
/// Safe to access at any time - not tied to SwiftData context.
@Observable
@MainActor
final class TabViewModel: Identifiable {
    let id: UUID
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

    // Cached query results (in-memory only, persisted separately)
    var cachedResults: [TableRow]?
    var cachedColumnNames: [String]?

    /// Track if this tab has been marked for deletion
    var isPendingDeletion: Bool = false

    // MARK: - Per-Tab Query Execution State

    /// Whether this tab has a query currently executing
    var isExecutingQuery: Bool = false

    /// When the current query started (for elapsed time calculation)
    var queryStartTime: Date? = nil

    /// Displayed elapsed time (updated by timer)
    var displayedElapsedTime: TimeInterval = 0

    /// The task running the current query (for cancellation)
    var currentQueryTask: Task<Void, Never>? = nil

    /// Timer task for updating elapsed time display
    private var elapsedTimeTimer: Task<Void, Never>? = nil

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
        cachedResults: [TableRow]? = nil,
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
        self.cachedResults = cachedResults
        self.cachedColumnNames = cachedColumnNames
    }

    /// Create from a TabState (SwiftData model)
    convenience init(from tabState: TabState) {
        self.init(
            id: tabState.id,
            connectionId: tabState.connectionId,
            databaseName: tabState.databaseName,
            queryText: tabState.queryText,
            savedQueryId: tabState.savedQueryId,
            isActive: tabState.isActive,
            order: tabState.order,
            createdAt: tabState.createdAt,
            lastAccessedAt: tabState.lastAccessedAt,
            selectedTableSchema: tabState.selectedTableSchema,
            selectedTableName: tabState.selectedTableName,
            selectedSchemaFilter: tabState.selectedSchemaFilter,
            cachedResults: tabState.cachedResults,
            cachedColumnNames: tabState.cachedColumnNames
        )
    }

    /// Create a snapshot of current state for safe async use
    func snapshot() -> TabSnapshot {
        TabSnapshot(
            id: id,
            connectionId: connectionId,
            databaseName: databaseName,
            queryText: queryText,
            savedQueryId: savedQueryId,
            isActive: isActive,
            order: order,
            selectedTableSchema: selectedTableSchema,
            selectedTableName: selectedTableName,
            selectedSchemaFilter: selectedSchemaFilter,
            cachedResults: cachedResults,
            cachedColumnNames: cachedColumnNames,
            isExecutingQuery: isExecutingQuery,
            displayedElapsedTime: displayedElapsedTime
        )
    }

    /// Clear cached results
    func clearCachedResults() {
        cachedResults = nil
        cachedColumnNames = nil
    }

    // MARK: - Query Execution Methods

    /// Start tracking a query execution on this tab
    func startQueryExecution() {
        isExecutingQuery = true
        queryStartTime = Date()
        displayedElapsedTime = 0

        // Start elapsed time timer
        elapsedTimeTimer?.cancel()
        elapsedTimeTimer = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                guard !Task.isCancelled, let self = self, let start = self.queryStartTime else { return }
                self.displayedElapsedTime = Date().timeIntervalSince(start)
            }
        }
    }

    /// Finish query execution on this tab
    func finishQueryExecution() {
        isExecutingQuery = false
        elapsedTimeTimer?.cancel()
        elapsedTimeTimer = nil
        currentQueryTask = nil
        // Keep queryStartTime and displayedElapsedTime for display purposes
    }

    /// Cancel the currently running query on this tab
    func cancelQuery() {
        currentQueryTask?.cancel()
        currentQueryTask = nil
        finishQueryExecution()
    }

    /// Format elapsed time for display
    static func formatElapsedTime(_ interval: TimeInterval) -> String {
        if interval < 60 {
            return String(format: "%.1fs", interval)
        } else {
            let minutes = Int(interval) / 60
            let seconds = interval.truncatingRemainder(dividingBy: 60)
            return String(format: "%d:%05.2f", minutes, seconds)
        }
    }
}

/// Immutable snapshot of tab state for passing across async boundaries
struct TabSnapshot: Sendable {
    let id: UUID
    let connectionId: UUID?
    let databaseName: String?
    let queryText: String
    let savedQueryId: UUID?
    let isActive: Bool
    let order: Int
    let selectedTableSchema: String?
    let selectedTableName: String?
    let selectedSchemaFilter: String?
    let cachedResults: [TableRow]?
    let cachedColumnNames: [String]?
    let isExecutingQuery: Bool
    let displayedElapsedTime: TimeInterval
}
