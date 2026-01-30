//
//  TabService.swift
//  PostgresGUI
//
//  Service for managing tab state persistence with SwiftData.
//  Handles syncing between in-memory TabViewModels and persistent TabState.
//
//  Architecture:
//  - TabViewModel (in-memory) = what UI interacts with
//  - TabState (SwiftData) = persistence only
//  - This service bridges the two layers
//

import Foundation
import SwiftData

@MainActor
class TabService: TabServiceProtocol {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Loading (SwiftData -> ViewModels)

    /// Load all tabs from SwiftData and convert to ViewModels
    func loadAllTabViewModels() -> [TabViewModel] {
        let descriptor = FetchDescriptor<TabState>(
            sortBy: [SortDescriptor(\.order, order: .forward)]
        )
        do {
            let tabStates = try modelContext.fetch(descriptor)
            return tabStates.map { TabViewModel(from: $0) }
        } catch {
            DebugLog.print("Failed to load tabs: \(error)")
            return []
        }
    }

    /// Get the active tab as ViewModel
    func getActiveTabViewModel() -> TabViewModel? {
        let descriptor = FetchDescriptor<TabState>(
            predicate: #Predicate<TabState> { $0.isActive == true }
        )
        do {
            if let tabState = try modelContext.fetch(descriptor).first {
                return TabViewModel(from: tabState)
            }
            return nil
        } catch {
            DebugLog.print("Failed to get active tab: \(error)")
            return nil
        }
    }

    // MARK: - Syncing (ViewModels -> SwiftData)

    /// Sync a TabViewModel back to its TabState in SwiftData
    func syncToStorage(_ viewModel: TabViewModel) {
        guard let tabState = fetchTabState(by: viewModel.id) else {
            DebugLog.print("⚠️ [TabService] Cannot sync - TabState not found for \(viewModel.id)")
            return
        }

        tabState.connectionId = viewModel.connectionId
        tabState.databaseName = viewModel.databaseName
        tabState.queryText = viewModel.queryText
        tabState.savedQueryId = viewModel.savedQueryId
        tabState.isActive = viewModel.isActive
        tabState.order = viewModel.order
        tabState.lastAccessedAt = viewModel.lastAccessedAt
        tabState.selectedTableSchema = viewModel.selectedTableSchema
        tabState.selectedTableName = viewModel.selectedTableName
        tabState.selectedSchemaFilter = viewModel.selectedSchemaFilter

        // Persist cached results for restoration after app restart
        tabState.setCachedResults(viewModel.cachedResults, columnNames: viewModel.cachedColumnNames)

        save()
    }

    /// Sync multiple ViewModels to storage
    func syncAllToStorage(_ viewModels: [TabViewModel]) {
        for viewModel in viewModels {
            guard !viewModel.isPendingDeletion else { continue }
            syncToStorage(viewModel)
        }
    }

    /// Set a tab as active (deactivates all others)
    func setActiveTab(_ viewModel: TabViewModel) {
        // Deactivate all tabs in storage
        let allTabs = loadAllTabs()
        for tabState in allTabs {
            tabState.isActive = false
        }

        // Activate the selected one
        if let tabState = fetchTabState(by: viewModel.id) {
            tabState.isActive = true
            tabState.lastAccessedAt = Date()
        }

        save()
    }

    /// Create a new tab and return its ViewModel
    func createTabViewModel(inheritingFrom viewModel: TabViewModel? = nil) -> TabViewModel {
        let allTabs = loadAllTabs()
        let maxOrder = allTabs.map(\.order).max() ?? -1

        let newTabState = TabState(
            connectionId: viewModel?.connectionId,
            databaseName: viewModel?.databaseName,
            queryText: "",
            isActive: false,
            order: maxOrder + 1
        )

        modelContext.insert(newTabState)
        save()

        return TabViewModel(from: newTabState)
    }

    /// Delete a tab from storage
    func deleteTabFromStorage(_ viewModel: TabViewModel) {
        guard let tabState = fetchTabState(by: viewModel.id) else {
            DebugLog.print("⚠️ [TabService] Cannot delete - TabState not found for \(viewModel.id)")
            return
        }

        modelContext.delete(tabState)
        save()
    }

    /// Update cached results for a tab (in-memory only, not persisted to disk)
    func updateTabResults(_ viewModel: TabViewModel, results: [TableRow]?, columnNames: [String]?) {
        DebugLog.print("💾 [TabService] Caching \(results?.count ?? 0) results for tab \(viewModel.id)")
        if let tabState = fetchTabState(by: viewModel.id) {
            tabState.setCachedResults(results, columnNames: columnNames)
            save()
        } else {
            DebugLog.print("⚠️ [TabService] Cannot cache - TabState not found for \(viewModel.id)")
        }
    }

    // MARK: - Legacy Protocol Conformance (for gradual migration)

    func loadAllTabs() -> [TabState] {
        let descriptor = FetchDescriptor<TabState>(
            sortBy: [SortDescriptor(\.order, order: .forward)]
        )
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            DebugLog.print("Failed to load tabs: \(error)")
            return []
        }
    }

    func getActiveTab() -> TabState? {
        let descriptor = FetchDescriptor<TabState>(
            predicate: #Predicate<TabState> { $0.isActive == true }
        )
        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            DebugLog.print("Failed to get active tab: \(error)")
            return nil
        }
    }

    func setActiveTab(_ tab: TabState) {
        let allTabs = loadAllTabs()
        for t in allTabs {
            t.isActive = false
        }
        tab.isActive = true
        tab.lastAccessedAt = Date()
        save()
    }

    func createTab(inheritingFrom tab: TabState? = nil) -> TabState {
        let allTabs = loadAllTabs()
        let maxOrder = allTabs.map(\.order).max() ?? -1

        let newTab = TabState(
            connectionId: tab?.connectionId,
            databaseName: tab?.databaseName,
            queryText: "",
            isActive: false,
            order: maxOrder + 1
        )

        modelContext.insert(newTab)
        save()
        return newTab
    }

    func updateTab(_ tab: TabState, connectionId: UUID?, databaseName: String?, queryText: String?, savedQueryId: UUID?) {
        if let connectionId = connectionId {
            tab.connectionId = connectionId
        }
        if let databaseName = databaseName {
            tab.databaseName = databaseName
        }
        if let queryText = queryText {
            tab.queryText = queryText
        }
        if let savedQueryId = savedQueryId {
            tab.savedQueryId = savedQueryId
        }
        save()
    }

    func updateTabTableSelection(_ tab: TabState, schema: String?, name: String?) {
        tab.selectedTableSchema = schema
        tab.selectedTableName = name
        save()
    }

    func updateTabResults(_ tab: TabState, results: [TableRow]?, columnNames: [String]?) {
        // Persist cached results to TabState for restoration after app restart
        tab.setCachedResults(results, columnNames: columnNames)
        save()
        DebugLog.print("💾 [TabService] Results cached to SwiftData")
    }

    func clearSavedQueryId(_ tab: TabState) {
        tab.savedQueryId = nil
        save()
    }

    func deleteTab(_ tab: TabState) {
        modelContext.delete(tab)
        save()
    }

    func save() {
        do {
            try modelContext.save()
        } catch {
            DebugLog.print("Failed to save tab state: \(error)")
        }
    }

    // MARK: - Private Helpers

    private func fetchTabState(by id: UUID) -> TabState? {
        let descriptor = FetchDescriptor<TabState>(
            predicate: #Predicate<TabState> { $0.id == id }
        )
        return try? modelContext.fetch(descriptor).first
    }
}
