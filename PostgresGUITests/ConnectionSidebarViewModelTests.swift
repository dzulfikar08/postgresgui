//
//  ConnectionSidebarViewModelTests.swift
//  PostgresGUITests
//
//  Unit tests for manual toolbar refresh behavior.
//

import Foundation
import SwiftData
import Testing
@testable import PostgresGUI

@MainActor
final class ToolbarRefreshMockDatabaseService: DatabaseServiceProtocol {
    var isConnected: Bool = true
    var connectedDatabase: String? = "postgres"

    func connect(host: String, port: Int, username: String, password: String, database: String, sslMode: SSLMode) async throws {
        isConnected = true
        connectedDatabase = database
    }

    func disconnect() async {
        isConnected = false
        connectedDatabase = nil
    }

    func shutdown() async {
        isConnected = false
        connectedDatabase = nil
    }

    func interruptInFlightTableBrowseLoadForSupersession() async {}

    func fetchDatabases() async throws -> [DatabaseInfo] { [] }
    func createDatabase(name: String) async throws {}
    func deleteDatabase(name: String) async throws {}
    func fetchTables(database: String) async throws -> [TableInfo] { [] }
    func fetchSchemas(database: String) async throws -> [String] { [] }
    func deleteTable(schema: String, table: String) async throws {}
    func truncateTable(schema: String, table: String) async throws {}
    func generateDDL(schema: String, table: String) async throws -> String { "" }
    func fetchAllTableData(schema: String, table: String) async throws -> ([TableRow], [String]) { ([], []) }
    func executeQuery(_ sql: String) async throws -> ([TableRow], [String]) { ([], []) }
    func executeDisplayQuery(_ sql: String) async throws -> ([TableRow], [String]) { ([], []) }
    func deleteRows(schema: String, table: String, primaryKeyColumns: [String], rows: [TableRow]) async throws {}
    func updateRow(schema: String, table: String, primaryKeyColumns: [String], originalRow: TableRow, updatedValues: [String : RowEditValue]) async throws {}
    func fetchPrimaryKeyColumns(schema: String, table: String) async throws -> [String] { [] }
    func fetchColumnInfo(schema: String, table: String) async throws -> [ColumnInfo] { [] }
}

@MainActor
final class ToolbarRefreshMockService: TableRefreshServiceProtocol {
    var refreshDelayNanoseconds: UInt64 = 0
    private(set) var refreshCallCount: Int = 0
    private(set) var refreshCompletionCount: Int = 0
    private(set) var refreshCancellationCount: Int = 0

    func loadTables(for database: DatabaseInfo, connection: ConnectionProfile, appState: AppState) async {}

    func refresh(appState: AppState) async {
        refreshCallCount += 1

        if refreshDelayNanoseconds > 0 {
            do {
                try await Task.sleep(nanoseconds: refreshDelayNanoseconds)
            } catch {
                refreshCancellationCount += 1
                return
            }
        }

        if Task.isCancelled {
            refreshCancellationCount += 1
            return
        }

        refreshCompletionCount += 1
    }
}

final class ToolbarRefreshMockUserDefaults: UserDefaultsProtocol {
    private var storage: [String: Any] = [:]

    func string(forKey key: String) -> String? {
        storage[key] as? String
    }

    func set(_ value: Any?, forKey key: String) {
        storage[key] = value
    }

    func removeObject(forKey key: String) {
        storage.removeValue(forKey: key)
    }
}

@MainActor
final class ToolbarRefreshMockKeychainService: KeychainServiceProtocol {
    func savePassword(_ password: String, for connectionId: UUID) throws {}
    func getPassword(for connectionId: UUID) throws -> String? { nil }
    func deletePassword(for connectionId: UUID) throws {}
}

@Suite("ConnectionSidebarViewModel")
struct ConnectionSidebarViewModelTests {
    @MainActor
    private func makeModelContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: ConnectionProfile.self,
            TabState.self,
            SavedQuery.self,
            QueryFolder.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @MainActor
    private func makeViewModel(
        refreshService: TableRefreshServiceProtocol
    ) throws -> ConnectionSidebarViewModel {
        let appState = AppState(
            connection: ConnectionState(databaseService: ToolbarRefreshMockDatabaseService()),
            query: QueryState()
        )
        return ConnectionSidebarViewModel(
            appState: appState,
            tabManager: TabManager(),
            loadingState: LoadingState(),
            modelContext: try makeModelContext(),
            keychainService: ToolbarRefreshMockKeychainService(),
            userDefaults: ToolbarRefreshMockUserDefaults(),
            tableRefreshService: refreshService
        )
    }

    @Test
    @MainActor
    func refreshOnDemandFromToolbar_invokesTableRefreshService() async throws {
        let refreshService = ToolbarRefreshMockService()
        let viewModel = try makeViewModel(refreshService: refreshService)

        await viewModel.refreshOnDemandFromToolbar()

        #expect(refreshService.refreshCallCount == 1)
        #expect(refreshService.refreshCompletionCount == 1)
    }

    @Test
    @MainActor
    func refreshOnDemandFromToolbar_cancelsPreviousManualRefreshTask() async throws {
        let refreshService = ToolbarRefreshMockService()
        refreshService.refreshDelayNanoseconds = 250_000_000
        let viewModel = try makeViewModel(refreshService: refreshService)

        let first = Task { await viewModel.refreshOnDemandFromToolbar() }
        try? await Task.sleep(nanoseconds: 20_000_000)
        let second = Task { await viewModel.refreshOnDemandFromToolbar() }

        await first.value
        await second.value

        #expect(refreshService.refreshCallCount == 2)
        #expect(refreshService.refreshCancellationCount >= 1)
        #expect(refreshService.refreshCompletionCount == 1)
    }
}
