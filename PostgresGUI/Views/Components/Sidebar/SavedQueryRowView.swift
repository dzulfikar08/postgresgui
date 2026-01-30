//
//  SavedQueryRowView.swift
//  PostgresGUI
//

import SwiftUI

struct SavedQueryRowView: View {
    @Environment(AppState.self) private var appState

    let query: SavedQuery
    let isSelected: Bool
    let selectedQueryCount: Int
    let selectedFolderCount: Int
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onDeleteSelectedQueries: () -> Void
    let onDeleteSelectedFolders: () -> Void
    let onDuplicate: () -> Void
    let onMoveToFolder: () -> Void

    @State private var isHovered = false
    @State private var isButtonHovered = false

    /// Whether this query is currently executing
    private var isExecuting: Bool {
        appState.query.executingSavedQueryId == query.id
    }

    private var showMultiSelectActions: Bool {
        isSelected && (selectedQueryCount > 1 || selectedFolderCount > 0)
    }

    private var hasMultipleQueries: Bool {
        selectedQueryCount > 1
    }

    private var hasFolders: Bool {
        selectedFolderCount > 0
    }

    private var cachedRowCount: Int {
        appState.query.getCachedResults(for: query.id)?.rows.count ?? 0
    }

    private var shouldShowCachedRowCount: Bool {
        cachedRowCount > 0
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Show loading indicator or document icon, with optional cached-results dot
            if isExecuting {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 16, height: 16)
            } else {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "doc.text")
                        .foregroundColor(.secondary)
                    if shouldShowCachedRowCount {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                            .offset(x: 2, y: -2)
                    }
                }
                .frame(width: 16, height: 16)
            }
            Text(query.name)
                .lineLimit(1)
            Spacer()
            menuButton
                .opacity(isHovered ? 1 : 0)
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 2)
        .tag(query.id)
        .onHover { isHovered = $0 }
        .contextMenu { menuContent }
    }

    // MARK: - Shared Menu Content

    @ViewBuilder
    private var menuContent: some View {
        if !showMultiSelectActions {
            Button {
                DebugLog.print("✏️ [SavedQueryRowView] Rename tapped for: \(query.name)")
                onEdit()
            } label: {
                Label("Rename...", systemImage: "pencil")
            }

            Button {
                DebugLog.print("📋 [SavedQueryRowView] Duplicate tapped for: \(query.name)")
                onDuplicate()
            } label: {
                Label("Duplicate", systemImage: "doc.on.doc")
            }

            Divider()
        }

        // Only show move option if we have queries (not just folders)
        if selectedQueryCount > 0 {
            Button {
                DebugLog.print(
                    "📁 [SavedQueryRowView] Move to folder tapped for: \(hasMultipleQueries ? "\(selectedQueryCount) queries" : query.name)"
                )
                onMoveToFolder()
            } label: {
                Label(
                    hasMultipleQueries
                        ? "Move \(selectedQueryCount) to Folder..." : "Move to Folder...",
                    systemImage: "folder")
            }

            Divider()
        }

        // Delete options - separate for folders and queries
        if hasFolders {
            Button(role: .destructive) {
                DebugLog.print(
                    "🗑️ [SavedQueryRowView] Delete \(selectedFolderCount) selected folders tapped")
                onDeleteSelectedFolders()
            } label: {
                Label(
                    selectedFolderCount == 1
                        ? "Delete Folder..." : "Delete \(selectedFolderCount) Folders...",
                    systemImage: "trash")
            }
        }

        if hasMultipleQueries {
            Button(role: .destructive) {
                DebugLog.print(
                    "🗑️ [SavedQueryRowView] Delete \(selectedQueryCount) selected queries tapped")
                onDeleteSelectedQueries()
            } label: {
                Label("Delete \(selectedQueryCount) Queries...", systemImage: "trash")
            }
        } else if !showMultiSelectActions {
            Button(role: .destructive) {
                DebugLog.print("🗑️ [SavedQueryRowView] Delete tapped for: \(query.name)")
                onDelete()
            } label: {
                Label("Delete...", systemImage: "trash")
            }
        } else if selectedQueryCount == 1 {
            // Single query selected along with folders
            Button(role: .destructive) {
                DebugLog.print("🗑️ [SavedQueryRowView] Delete tapped for: \(query.name)")
                onDelete()
            } label: {
                Label("Delete Query...", systemImage: "trash")
            }
        }
    }

    // MARK: - Menu Button

    private var menuButton: some View {
        Menu {
            menuContent
        } label: {
            Image(systemName: "ellipsis")
                .foregroundColor(isButtonHovered ? .primary : .secondary)
                .padding(6)
                .background(isButtonHovered ? Color.secondary.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .onHover { isButtonHovered = $0 }
    }
}
