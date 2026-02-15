//
//  QueryStateTests.swift
//  PostgresGUITests
//
//  Unit tests for QueryState.
//

import Foundation
import Testing
@testable import PostgresGUI

@Suite("QueryState")
struct QueryStateTests {

    // MARK: - formatExecutionTime Tests

    @Suite("formatExecutionTime")
    @MainActor
    struct FormatExecutionTimeTests {

        @Test func formatsMilliseconds() {
            let result = QueryState.formatExecutionTime(0.5)
            #expect(result == "500 ms")
        }

        @Test func formatsOneMillisecond() {
            let result = QueryState.formatExecutionTime(0.001)
            #expect(result == "1 ms")
        }

        @Test func formatsTenMilliseconds() {
            let result = QueryState.formatExecutionTime(0.010)
            #expect(result == "10 ms")
        }

        @Test func formatsHundredMilliseconds() {
            let result = QueryState.formatExecutionTime(0.100)
            #expect(result == "100 ms")
        }

        @Test func formatsOneSecond() {
            let result = QueryState.formatExecutionTime(1.0)
            #expect(result == "1.00 s")
        }

        @Test func formatsFiveSeconds() {
            let result = QueryState.formatExecutionTime(5.0)
            #expect(result == "5.00 s")
        }

        @Test func formatsTwoPointFiveSeconds() {
            let result = QueryState.formatExecutionTime(2.5)
            #expect(result == "2.50 s")
        }

        @Test func formatsJustUnderOneSecond() {
            let result = QueryState.formatExecutionTime(0.999)
            #expect(result == "999 ms")
        }

        @Test func formatsZero() {
            let result = QueryState.formatExecutionTime(0.0)
            #expect(result == "0 ms")
        }

        @Test func formatsVerySmallValue() {
            let result = QueryState.formatExecutionTime(0.0001)
            // 0.1 ms rounds to 0 ms
            #expect(result == "0 ms")
        }

        @Test func formatsLargeValue() {
            let result = QueryState.formatExecutionTime(60.0)
            #expect(result == "60.00 s")
        }

        @Test func formatsDecimalSeconds() {
            let result = QueryState.formatExecutionTime(1.234)
            #expect(result == "1.23 s")
        }
    }

    // MARK: - State Initialization Tests

    @Suite("State Initialization")
    @MainActor
    struct StateInitializationTests {

        @Test func initialStateHasEmptyQueryText() {
            let state = QueryState()
            #expect(state.queryText == "")
        }

        @Test func initialStateHasEmptyResults() {
            let state = QueryState()
            #expect(state.queryResults.isEmpty)
        }

        @Test func initialStateHasNilColumnNames() {
            let state = QueryState()
            #expect(state.queryColumnNames == nil)
        }

        @Test func initialStateIsNotExecuting() {
            let state = QueryState()
            #expect(state.isExecutingQuery == false)
        }

        @Test func initialStateHasNoError() {
            let state = QueryState()
            #expect(state.queryError == nil)
        }

        @Test func initialStateDoesNotShowResults() {
            let state = QueryState()
            #expect(state.showQueryResults == false)
        }

        @Test func initialStateHasNoExecutionTime() {
            let state = QueryState()
            #expect(state.queryExecutionTime == nil)
        }

        @Test func initialStateHasEmptySelectedRows() {
            let state = QueryState()
            #expect(state.selectedRowIDs.isEmpty)
        }

        @Test func initialStateIsOnFirstPage() {
            let state = QueryState()
            #expect(state.currentPage == 0)
        }

        @Test func initialStateHasDefaultRowsPerPage() {
            let state = QueryState()
            #expect(state.rowsPerPage == Constants.Pagination.defaultRowsPerPage)
        }

        @Test func initialStateRowsPerPageIs100() {
            let state = QueryState()
            #expect(state.rowsPerPage == 100)
        }

        @Test func initialStateHasNoNextPage() {
            let state = QueryState()
            #expect(state.hasNextPage == false)
        }
    }

    // MARK: - Query Execution State Tests

    @Suite("Query Execution State")
    @MainActor
    struct QueryExecutionStateTests {

        @Test func startQueryExecutionSetsLoadingState() {
            let state = QueryState()
            state.startQueryExecution()
            #expect(state.isExecutingQuery == true)
        }

        @Test func startQueryExecutionClearsError() {
            let state = QueryState()
            state.queryError = NSError(domain: "test", code: 1)
            state.startQueryExecution()
            #expect(state.queryError == nil)
        }

        @Test func startQueryExecutionClearsExecutionTime() {
            let state = QueryState()
            state.queryExecutionTime = 1.5
            state.startQueryExecution()
            #expect(state.queryExecutionTime == nil)
        }

        @Test func finishQueryExecutionWithSuccessSetsResults() {
            let state = QueryState()
            state.startQueryExecution()

            let rows = [
                TableRow(values: ["id": "1"]),
                TableRow(values: ["id": "2"])
            ]
            let result = QueryResult.success(rows: rows, columnNames: ["id"], executionTime: 0.5)
            state.finishQueryExecution(with: result)

            #expect(state.isExecutingQuery == false)
            #expect(state.queryResults.count == 2)
            #expect(state.queryColumnNames == ["id"])
            #expect(state.queryExecutionTime == 0.5)
            #expect(state.showQueryResults == true)
        }

        @Test func finishQueryExecutionWithErrorSetsError() {
            let state = QueryState()
            state.startQueryExecution()

            let error = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test error"])
            let result = QueryResult.failure(error: error, executionTime: 0.1)
            state.finishQueryExecution(with: result)

            #expect(state.isExecutingQuery == false)
            #expect(state.queryError != nil)
            #expect(state.showQueryResults == true)
        }

        @Test func updateQueryResultsSetsResultsAndColumns() {
            let state = QueryState()
            let rows = [TableRow(values: ["name": "Alice"])]
            state.updateQueryResults(rows, columnNames: ["name"])

            #expect(state.queryResults.count == 1)
            #expect(state.queryColumnNames == ["name"])
            #expect(state.showQueryResults == true)
        }

        @Test func updateQueryResultsWithEmptyColumnsNilsColumnNames() {
            let state = QueryState()
            let rows = [TableRow(values: ["name": "Alice"])]
            state.updateQueryResults(rows, columnNames: [])

            #expect(state.queryColumnNames == nil)
        }

        @Test func clearQueryResultsClearsAll() {
            let state = QueryState()
            state.queryResults = [TableRow(values: ["id": "1"])]
            state.queryColumnNames = ["id"]
            state.showQueryResults = true
            state.selectedRowIDs = [UUID()]

            state.clearQueryResults()

            #expect(state.showQueryResults == false)
            #expect(state.queryResults.isEmpty)
            #expect(state.queryColumnNames == nil)
            #expect(state.selectedRowIDs.isEmpty)
        }
    }

    // MARK: - Query Counter Tests

    @Suite("Query Counter")
    @MainActor
    struct QueryCounterTests {

        @Test func initialQueryCounterIsZero() {
            let state = QueryState()
            #expect(state.queryCounter == 0)
        }

        @Test func cancelCurrentQueryIncrementsCounter() {
            let state = QueryState()
            let initialCounter = state.queryCounter
            state.cancelCurrentQuery()
            #expect(state.queryCounter == initialCounter + 1)
        }

        @Test func cancelCurrentQueryClearsTask() {
            let state = QueryState()
            state.currentQueryTask = Task { }
            state.cancelCurrentQuery()
            #expect(state.currentQueryTask == nil)
        }

        @Test func cancelCurrentQuerySilentlyForSupersession_preservesResults() {
            let state = QueryState()
            state.queryResults = [TableRow(values: ["id": "1"])]
            state.queryColumnNames = ["id"]
            state.showQueryResults = true
            state.statusMessage = "Existing status"
            state.currentQueryTask = Task { }

            let initialCounter = state.queryCounter
            state.cancelCurrentQuerySilentlyForSupersession()

            #expect(state.currentQueryTask == nil)
            #expect(state.queryCounter == initialCounter + 1)
            #expect(state.queryResults.count == 1)
            #expect(state.queryColumnNames == ["id"])
            #expect(state.showQueryResults == true)
            #expect(state.statusMessage == "Existing status")
        }
    }

    // MARK: - Results Version Tests

    @Suite("Results Version")
    @MainActor
    struct ResultsVersionTests {

        @Test func initialResultsVersionIsZero() {
            let state = QueryState()
            #expect(state.resultsVersion == 0)
        }

        @Test func resultsVersionCanBeIncremented() {
            let state = QueryState()
            state.resultsVersion += 1
            #expect(state.resultsVersion == 1)
        }
    }

    // MARK: - Reset Tests

    @Suite("Reset")
    @MainActor
    struct ResetTests {

        @Test func resetClearsQueryText() {
            let state = QueryState()
            state.queryText = "SELECT * FROM users"
            state.reset()
            #expect(state.queryText == "")
        }

        @Test func resetClearsResults() {
            let state = QueryState()
            state.queryResults = [TableRow(values: ["id": "1"])]
            state.reset()
            #expect(state.queryResults.isEmpty)
        }

        @Test func resetClearsColumnNames() {
            let state = QueryState()
            state.queryColumnNames = ["id", "name"]
            state.reset()
            #expect(state.queryColumnNames == nil)
        }

        @Test func resetClearsCachedTableId() {
            let state = QueryState()
            state.cachedResultsTableId = "public.users"
            state.reset()
            #expect(state.cachedResultsTableId == nil)
        }

        @Test func resetClearsExecutingState() {
            let state = QueryState()
            state.isExecutingQuery = true
            state.reset()
            #expect(state.isExecutingQuery == false)
        }

        @Test func resetClearsError() {
            let state = QueryState()
            state.queryError = NSError(domain: "test", code: 1)
            state.reset()
            #expect(state.queryError == nil)
        }

        @Test func resetClearsShowResults() {
            let state = QueryState()
            state.showQueryResults = true
            state.reset()
            #expect(state.showQueryResults == false)
        }

        @Test func resetClearsTableLoadingFlags() {
            let state = QueryState()
            state.isExecutingTableQuery = true
            state.executingTableQueryTableId = "public.users"

            state.reset()

            #expect(state.isExecutingTableQuery == false)
            #expect(state.executingTableQueryTableId == nil)
        }

        @Test func resetClearsExecutionTime() {
            let state = QueryState()
            state.queryExecutionTime = 1.5
            state.reset()
            #expect(state.queryExecutionTime == nil)
        }

        @Test func resetClearsSelectedRows() {
            let state = QueryState()
            state.selectedRowIDs = [UUID(), UUID()]
            state.reset()
            #expect(state.selectedRowIDs.isEmpty)
        }

        @Test func resetResetsPagination() {
            let state = QueryState()
            state.currentPage = 5
            state.hasNextPage = true
            state.reset()
            #expect(state.currentPage == 0)
            #expect(state.hasNextPage == false)
        }

        @Test func resetClearsSavedQueryState() {
            let state = QueryState()
            state.currentSavedQueryId = UUID()
            state.lastSavedAt = Date()
            state.currentQueryName = "My Query"
            state.reset()
            #expect(state.currentSavedQueryId == nil)
            #expect(state.lastSavedAt == nil)
            #expect(state.currentQueryName == nil)
        }

        @Test func resetClearsStatusMessage() {
            let state = QueryState()
            state.statusMessage = "Loading..."
            state.reset()
            #expect(state.statusMessage == nil)
        }

        @Test func resetClearsMutationToast() {
            let state = QueryState()
            state.mutationToast = MutationToastData(title: "Inserted", tableName: "users", queryType: .insert)
            state.reset()
            #expect(state.mutationToast == nil)
        }
    }

    // MARK: - Cleanup Tests

    @Suite("Cleanup")
    @MainActor
    struct CleanupTests {

        @Test func cleanupCallsCancelAndReset() {
            let state = QueryState()
            state.queryText = "SELECT 1"
            state.queryResults = [TableRow(values: ["a": "1"])]
            state.currentPage = 3

            state.cleanup()

            #expect(state.queryText == "")
            #expect(state.queryResults.isEmpty)
            #expect(state.currentPage == 0)
        }
    }

    // MARK: - Error Message Tests

    @Suite("Error Message")
    @MainActor
    struct ErrorMessageTests {

        @Test func queryErrorMessageIsNilWhenNoError() {
            let state = QueryState()
            #expect(state.queryErrorMessage == nil)
        }

        @Test func queryErrorMessageExtractsFromError() {
            let state = QueryState()
            state.queryError = ConnectionError.networkUnreachable
            #expect(state.queryErrorMessage != nil)
            #expect(state.queryErrorMessage?.isEmpty == false)
        }
    }

    // MARK: - Toast Tests

    @Suite("Toast")
    @MainActor
    struct ToastTests {

        @Test func dismissMutationToastClearsToast() {
            let state = QueryState()
            state.mutationToast = MutationToastData(title: "Test", tableName: "t", queryType: .insert)

            state.dismissMutationToast()

            #expect(state.mutationToast == nil)
            #expect(state.toastTimer == nil)
        }
    }

    // MARK: - Date Parse Gating Tests

    @Suite("Date Parse Gating")
    struct DateParseGatingTests {

        @Test func obviousNonDateLongText_skipsParseAttempt() {
            let longText = String(repeating: "x", count: QueryResultsComponent.maxDateParseLength + 1)
            #expect(QueryResultsComponent.shouldAttemptDateParsing(longText) == false)
        }

        @Test func likelyDateValue_attemptsParse() {
            #expect(QueryResultsComponent.shouldAttemptDateParsing("2026-02-15T10:30:00Z") == true)
        }
    }
}
