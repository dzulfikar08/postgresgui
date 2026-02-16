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
    func executeQuery(_ sql: String, preferredColumnOrder: [String]? = nil) async -> QueryResult {
        let startTime = clock.now()

        do {
            let (normalizedRows, normalizedColumnNames) = try await fetchAndNormalizeDisplayRows(
                sql: sql,
                preferredColumnOrder: preferredColumnOrder
            )
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
        offset: Int = 0,
        preferredColumnOrder: [String]? = nil
    ) async -> QueryResult {
        if Task.isCancelled {
            return .failure(
                error: CancellationError(),
                executionTime: 0
            )
        }

        // Cancel any existing query task
        queryState.currentQueryTask?.cancel()
        queryState.currentQueryTask = nil

        // Increment counter to track which query is active
        queryState.queryCounter += 1
        let thisQueryID = queryState.queryCounter

        DebugLog.print("🔍 [QueryService] Auto-generating query for table: \(table.schema).\(table.name) (ID: \(thisQueryID))")

        let query = makeWrappedTableBrowseQuery(
            schema: table.schema,
            table: table.name,
            limit: limit,
            offset: offset
        )
        DebugLog.print("📝 [QueryService] Generated query: \(query) (ID: \(thisQueryID))")

        let startTime = clock.now()

        // Create result that will be returned
        var result: QueryResult?

        // Create and store the task
        queryState.currentQueryTask = Task { @MainActor in
            do {
                guard !Task.isCancelled else { return }
                DebugLog.print("📊 [QueryService] Executing query... (ID: \(thisQueryID))")
                let (normalizedRows, normalizedColumnNames) = try await fetchAndNormalizeDisplayRows(
                    sql: query,
                    preferredColumnOrder: preferredColumnOrder,
                    queryId: thisQueryID,
                    useDisplayWrapping: false
                )

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

                DebugLog.print("✅ [QueryService] Query executed successfully - \(normalizedRows.count) rows (ID: \(thisQueryID))")
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

    private func fetchAndNormalizeDisplayRows(
        sql: String,
        preferredColumnOrder: [String]? = nil,
        queryId: Int? = nil,
        useDisplayWrapping: Bool = true
    ) async throws -> ([TableRow], [String]) {
        try Task.checkCancellation()

        let dbFetchStart = clock.now()
        let (rows, columnNames) = try await withDatabaseTimeout {
            if useDisplayWrapping {
                return try await self.databaseService.executeDisplayQuery(sql)
            } else {
                return try await self.databaseService.executeQuery(sql)
            }
        }
        let dbFetchDuration = clock.now().timeIntervalSince(dbFetchStart)

        try Task.checkCancellation()

        let normalizationStart = clock.now()
        let (normalizedRows, normalizedColumnNames) = await QueryResultNormalizer
            .normalizeDisplayRowsOffMain(
                rows: rows,
                columnNames: columnNames,
                preferredColumnOrder: preferredColumnOrder
            )
        let normalizationDuration = clock.now().timeIntervalSince(normalizationStart)

        try Task.checkCancellation()

        let queryIdSuffix = queryId.map { " (ID: \($0))" } ?? ""
        DebugLog.print(
            "⏱️ [QueryService] DB fetch \(String(format: "%.3f", dbFetchDuration))s, " +
            "normalize \(String(format: "%.3f", normalizationDuration))s, " +
            "rows \(rows.count)→\(normalizedRows.count), cols \(columnNames.count)→\(normalizedColumnNames.count)\(queryIdSuffix)"
        )

        return (normalizedRows, normalizedColumnNames)
    }

    private func makeWrappedTableBrowseQuery(
        schema: String,
        table: String,
        limit: Int,
        offset: Int
    ) -> String {
        let baseQuery = "SELECT * FROM \"\(schema)\".\"\(table)\" LIMIT \(limit) OFFSET \(offset)"
        return """
        SELECT to_jsonb(q) AS row
        FROM (
        \(baseQuery)
        ) q
        """
    }
}
