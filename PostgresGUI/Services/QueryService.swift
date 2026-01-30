//
//  QueryService.swift
//  PostgresGUI
//
//  Created by ghazi on 12/17/25.
//

import Foundation

/// Service for query execution
/// Consolidates query logic that was previously duplicated across AppState, QueryEditorView, and DetailContentViewModel
@MainActor
class QueryService: QueryServiceProtocol {
    private let databaseService: DatabaseServiceProtocol
    private let queryState: QueryState
    private let clock: ClockProtocol

    init(databaseService: DatabaseServiceProtocol, queryState: QueryState, clock: ClockProtocol? = nil) {
        self.databaseService = databaseService
        self.queryState = queryState
        self.clock = clock ?? SystemClock()
    }

    /// Execute a SQL query with timeout
    func executeQuery(_ sql: String) async -> QueryResult {
        let startTime = clock.now()

        do {
            let (rows, columnNames) = try await withDatabaseTimeout {
                try await self.databaseService.executeDisplayQuery(sql)
            }
            let (normalizedRows, normalizedColumnNames) = QueryResultNormalizer
                .normalizeDisplayRows(rows: rows, columnNames: columnNames)
            let endTime = clock.now()
            let executionTime = endTime.timeIntervalSince(startTime)

            return .success(
                rows: normalizedRows,
                columnNames: normalizedColumnNames,
                executionTime: executionTime
            )
        } catch {
            let endTime = clock.now()
            let executionTime = endTime.timeIntervalSince(startTime)
            return .failure(error: error, executionTime: executionTime)
        }
    }

    /// Execute a table query with automatic SQL generation and race condition prevention
    func executeTableQuery(
        for table: TableInfo,
        limit: Int = 100,
        offset: Int = 0
    ) async -> QueryResult {
        // Cancel any existing query task
        queryState.currentQueryTask?.cancel()
        queryState.currentQueryTask = nil

        // Increment counter to track which query is active
        queryState.queryCounter += 1
        let thisQueryID = queryState.queryCounter

        DebugLog.print("🔍 [QueryService] Auto-generating query for table: \(table.schema).\(table.name) (ID: \(thisQueryID))")

        let query = "SELECT * FROM \"\(table.schema)\".\"\(table.name)\" LIMIT \(limit) OFFSET \(offset);"
        DebugLog.print("📝 [QueryService] Generated query: \(query) (ID: \(thisQueryID))")

        let startTime = clock.now()

        // Create result that will be returned
        var result: QueryResult?

        // Create and store the task
        queryState.currentQueryTask = Task { @MainActor in
            do {
                DebugLog.print("📊 [QueryService] Executing query... (ID: \(thisQueryID))")
                let (rows, columnNames) = try await withDatabaseTimeout {
                    try await self.databaseService.executeDisplayQuery(query)
                }
                let (normalizedRows, normalizedColumnNames) = QueryResultNormalizer
                    .normalizeDisplayRows(rows: rows, columnNames: columnNames)

                // Check if task was cancelled or a newer query has started
                guard !Task.isCancelled, thisQueryID == queryState.queryCounter else {
                    DebugLog.print("⚠️ [QueryService] Query was cancelled or superseded (ID: \(thisQueryID), current: \(queryState.queryCounter))")
                    return
                }

                let endTime = clock.now()
                let executionTime = endTime.timeIntervalSince(startTime)

                result = .success(
                    rows: normalizedRows,
                    columnNames: normalizedColumnNames,
                    executionTime: executionTime
                )

                DebugLog.print("✅ [QueryService] Query executed successfully - \(rows.count) rows (ID: \(thisQueryID))")
            } catch {
                // Check if task was cancelled or a newer query has started
                guard !Task.isCancelled, thisQueryID == queryState.queryCounter else {
                    DebugLog.print("⚠️ [QueryService] Query was cancelled or superseded during error handling (ID: \(thisQueryID), current: \(queryState.queryCounter))")
                    return
                }

                let endTime = clock.now()
                let executionTime = endTime.timeIntervalSince(startTime)

                result = .failure(error: error, executionTime: executionTime)

                DebugLog.print("❌ [QueryService] Query execution failed: \(error) (ID: \(thisQueryID))")
            }

            // Clean up task if not cancelled
            if queryState.currentQueryTask?.isCancelled == false {
                queryState.currentQueryTask = nil
            }
        }

        // Wait for task to complete
        await queryState.currentQueryTask?.value

        // Return result or a default failure if somehow nil
        return result ?? .failure(
            error: NSError(domain: "QueryService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Query was cancelled"]),
            executionTime: clock.now().timeIntervalSince(startTime)
        )
    }

    /// Cancel the currently running query
    func cancelCurrentQuery() {
        queryState.cancelCurrentQuery()
    }
}
