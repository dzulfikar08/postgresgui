//
//  TabManager.swift
//  PostgresGUI
//
//  Manages in-memory tab state using TabViewModels.
//  UI interacts with ViewModels, which are synced to SwiftData storage
//  at controlled moments (not during rapid operations).
//
//  This architecture prevents crashes when tabs are deleted while
//  async operations are in flight.
//
//  Created by ghazi on 12/20/25.
//

import Foundation
import SwiftData

@Observable
@MainActor
class TabManager {
    /// In-memory tabs - UI works with these, never with SwiftData directly
    var tabs: [TabViewModel] = []

    /// Currently active tab
    var activeTab: TabViewModel?

    private var tabService: TabService?

    // MARK: - Initialization

    func initialize(with modelContext: ModelContext) {
        self.tabService = TabService(modelContext: modelContext)
        loadTabs()
    }

    private func loadTabs() {
        guard let tabService = tabService else { return }

        // Load from SwiftData into ViewModels
        tabs = tabService.loadAllTabViewModels()

        // Find active tab
        activeTab = tabs.first(where: { $0.isActive })

        DebugLog.print("📑 [TabManager] Loaded \(tabs.count) tabs, activeTab: \(activeTab?.id.uuidString ?? "nil")")
        for tab in tabs {
            DebugLog.print("   Tab: \(tab.id) - connection: \(tab.connectionId?.uuidString ?? "nil"), db: \(tab.databaseName ?? "nil"), active: \(tab.isActive)")
        }

        // If no tabs exist, create one
        if tabs.isEmpty {
            DebugLog.print("📑 [TabManager] No tabs found, creating new one")
            let newTab = tabService.createTabViewModel(inheritingFrom: nil)
            newTab.isActive = true
            tabService.setActiveTab(newTab)
            tabs = [newTab]
            activeTab = newTab
        }

        // If no active tab but tabs exist, set first as active
        if activeTab == nil, let firstTab = tabs.first {
            DebugLog.print("📑 [TabManager] No active tab, setting first as active")
            firstTab.isActive = true
            tabService.setActiveTab(firstTab)
            activeTab = firstTab
        }
    }

    // MARK: - Tab Operations

    func createNewTab(inheritingFrom tab: TabViewModel? = nil) {
        guard let tabService = tabService else { return }

        let sourceTab = tab ?? activeTab
        let newTab = tabService.createTabViewModel(inheritingFrom: sourceTab)

        // Update in-memory state
        if let current = activeTab {
            current.isActive = false
        }
        newTab.isActive = true
        newTab.lastAccessedAt = Date()

        tabs.append(newTab)
        activeTab = newTab

        // Sync to storage
        tabService.setActiveTab(newTab)
    }

    func switchToTab(_ tab: TabViewModel) {
        guard let tabService = tabService else { return }
        guard !tab.isPendingDeletion else { return }

        // Update in-memory state
        if let current = activeTab {
            current.isActive = false
        }
        tab.isActive = true
        tab.lastAccessedAt = Date()
        activeTab = tab

        // Sync to storage
        tabService.setActiveTab(tab)
    }

    func closeTab(_ tab: TabViewModel) {
        guard let tabService = tabService else { return }

        // Mark as pending deletion immediately (prevents any further access)
        tab.isPendingDeletion = true

        let wasActive = tab.id == activeTab?.id

        // Remove from in-memory array first
        tabs.removeAll { $0.id == tab.id }

        // Delete from storage
        tabService.deleteTabFromStorage(tab)

        // If we closed the active tab, activate the most recently used one
        if wasActive {
            if let mruTab = tabs
                .filter({ !$0.isPendingDeletion })
                .max(by: { $0.lastAccessedAt < $1.lastAccessedAt }) {
                mruTab.isActive = true
                mruTab.lastAccessedAt = Date()
                activeTab = mruTab
                tabService.setActiveTab(mruTab)
            } else {
                // No tabs left, create a new one
                let newTab = tabService.createTabViewModel(inheritingFrom: nil)
                newTab.isActive = true
                tabService.setActiveTab(newTab)
                tabs = [newTab]
                activeTab = newTab
            }
        }
    }

    // MARK: - Tab Updates (in-memory, synced on demand)

    func updateActiveTab(
        connectionId: UUID? = nil,
        databaseName: String? = nil,
        queryText: String? = nil,
        savedQueryId: UUID? = nil
    ) {
        guard let activeTab = activeTab, !activeTab.isPendingDeletion else { return }

        if let connectionId = connectionId {
            activeTab.connectionId = connectionId
        }
        if let databaseName = databaseName {
            activeTab.databaseName = databaseName
        }
        if let queryText = queryText {
            activeTab.queryText = queryText
        }
        if let savedQueryId = savedQueryId {
            activeTab.savedQueryId = savedQueryId
        }

        // Sync to storage
        tabService?.syncToStorage(activeTab)
    }

    func updateActiveTabTableSelection(schema: String?, name: String?) {
        guard let activeTab = activeTab, !activeTab.isPendingDeletion else { return }

        activeTab.selectedTableSchema = schema
        activeTab.selectedTableName = name

        // Sync to storage
        tabService?.syncToStorage(activeTab)
    }

    func updateActiveTabSchemaFilter(_ schemaFilter: String?) {
        guard let activeTab = activeTab, !activeTab.isPendingDeletion else { return }

        activeTab.selectedSchemaFilter = schemaFilter

        // Sync to storage
        tabService?.syncToStorage(activeTab)
    }

    func updateActiveTabResults(results: [TableRow]?, columnNames: [String]?) {
        guard let activeTab = activeTab, !activeTab.isPendingDeletion else { return }


        activeTab.cachedResults = results
        activeTab.cachedColumnNames = columnNames

        // Sync to storage
        tabService?.updateTabResults(activeTab, results: results, columnNames: columnNames)
    }

    func clearActiveTabSavedQueryId() {
        guard let activeTab = activeTab, !activeTab.isPendingDeletion else { return }

        activeTab.savedQueryId = nil

        // Sync to storage
        tabService?.syncToStorage(activeTab)
    }

    // MARK: - Persistence

    func saveCurrentState() {
        guard let tabService = tabService else { return }
        tabService.syncAllToStorage(tabs.filter { !$0.isPendingDeletion })
    }

    /// Get a safe snapshot of tab for async operations
    func snapshotActiveTab() -> TabSnapshot? {
        guard let activeTab = activeTab, !activeTab.isPendingDeletion else { return nil }
        return activeTab.snapshot()
    }

    /// Check if a tab is still valid (not deleted)
    func isTabValid(_ tabId: UUID) -> Bool {
        tabs.contains { $0.id == tabId && !$0.isPendingDeletion }
    }

    /// Get tab by ID (returns nil if deleted or pending deletion)
    func tab(by id: UUID) -> TabViewModel? {
        tabs.first { $0.id == id && !$0.isPendingDeletion }
    }
}
