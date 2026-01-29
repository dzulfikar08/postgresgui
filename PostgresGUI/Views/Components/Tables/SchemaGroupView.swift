//
//  SchemaGroupView.swift
//  PostgresGUI
//
//  Collapsible disclosure group for tables in a schema.
//  Uses Section with conditional rendering instead of DisclosureGroup
//  to avoid eager view construction of collapsed content.
//  Implements incremental loading for large table counts.
//

import SwiftUI

struct SchemaGroupView: View {
    let group: SchemaGroup
    @Binding var isExpanded: Bool
    let isExecutingQuery: Bool
    let refreshQueryAction: (TableInfo) async -> Void

    /// Number of tables to load per batch for incremental rendering
    private static let batchSize = 100

    /// Current number of tables to display (for incremental loading)
    @State private var displayedCount: Int = SchemaGroupView.batchSize
    @State private var isHovered = false

    /// Tables to display (limited for performance)
    private var displayedTables: ArraySlice<TableInfo> {
        group.tables.prefix(displayedCount)
    }

    /// Whether there are more tables to load
    private var hasMoreTables: Bool {
        displayedCount < group.tables.count
    }

    var body: some View {
        Section {
            // Only render tables when expanded - prevents eager view construction
            if isExpanded {
                ForEach(displayedTables, id: \.id) { table in
                    TableListRowView(
                        table: table,
                        isExecutingQuery: isExecutingQuery,
                        refreshQueryAction: refreshQueryAction,
                        showSchemaPrefix: false
                    )
                    .listRowSeparator(.visible)
                }

                // "Load more" button when there are more tables to show
                if hasMoreTables {
                    Button {
                        displayedCount = min(displayedCount + Self.batchSize, group.tables.count)
                    } label: {
                        HStack {
                            Spacer()
                            Text("Load more (\(group.tables.count - displayedCount) remaining)")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            schemaHeader
        }
        .onChange(of: isExpanded) { _, newValue in
            if !newValue {
                // Reset pagination when collapsed
                displayedCount = Self.batchSize
            }
        }
    }

    private var schemaHeader: some View {
        HStack {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .frame(width: 12)
            HStack(spacing: 4) {
                Image(systemName: "folder")
                    .foregroundColor(.secondary)
                Text(group.name)
                    .foregroundColor(.primary)
            }
            Spacer()
            Text("\(group.tableCount)")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15))
                .clipShape(Capsule())
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(isHovered ? Color.secondary.opacity(0.2) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
    }
}
