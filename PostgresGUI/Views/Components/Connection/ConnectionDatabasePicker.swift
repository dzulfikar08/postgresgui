//
//  ConnectionDatabasePicker.swift
//  PostgresGUI
//

import SwiftUI

/// Font sizes used in the connection/database picker
private enum PickerFontSize {
    static let label: CGFloat = Constants.FontSize.small
    static let separator: CGFloat = 9
    static let chevron: CGFloat = 8
    static let dropdownItem: CGFloat = 12
    static let checkmark: CGFloat = Constants.FontSize.smallIcon
    static let deleteIcon: CGFloat = Constants.FontSize.small
}

/// Compact picker showing current connection and database with dropdown
struct ConnectionDatabasePicker: View {
    @Environment(AppState.self) private var appState

    // Connection dropdown
    @Binding var showConnectionDropdown: Bool
    let connections: [ConnectionProfile]
    let onSelectConnection: (ConnectionProfile) -> Void
    let onEditConnection: (ConnectionProfile) -> Void
    let onDeleteConnection: (ConnectionProfile) -> Void
    let onCreateConnection: () -> Void

    // Database dropdown
    @Binding var showDatabaseDropdown: Bool
    let onSelectDatabase: (DatabaseInfo) -> Void
    let onDeleteDatabase: (DatabaseInfo) -> Void
    let onCreateDatabase: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            ConnectionDropdown(
                isOpen: $showConnectionDropdown,
                connections: connections,
                onSelect: onSelectConnection,
                onEdit: onEditConnection,
                onDelete: onDeleteConnection,
                onCreate: onCreateConnection
            )
            if hasConnection {
                separatorChevron
                databasePickerButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(Color(nsColor: .quaternarySystemFill))
    }

    private var hasConnection: Bool {
        appState.connection.currentConnection != nil
    }

    // MARK: - Separator

    private var separatorChevron: some View {
        Text("|")
            .font(.system(size: PickerFontSize.label, weight: .light))
            .foregroundStyle(.tertiary)
    }

    // MARK: - Database Picker

    private var noDatabaseSelected: Bool {
        appState.connection.isConnected && appState.connection.selectedDatabase == nil
    }

    @ViewBuilder
    private var databasePickerButton: some View {
        Button {
            showDatabaseDropdown.toggle()
        } label: {
            if noDatabaseSelected {
                PhaseAnimator([0.4, 1.0]) { phase in
                    databaseButtonContent(opacity: phase)
                } animation: { _ in
                    .easeInOut(duration: 0.8)
                }
            } else {
                databaseButtonContent(opacity: 1.0)
            }
        }
        .buttonStyle(.plain)
        .disabled(!appState.connection.isConnected)
        .popover(isPresented: $showDatabaseDropdown, arrowEdge: .bottom) {
            databaseDropdownContent
        }
    }

    private func databaseButtonContent(opacity: Double) -> some View {
        HStack(spacing: 6) {
            if let database = appState.connection.selectedDatabase {
                Image(systemName: "cylinder.split.1x2")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                Text(database.name)
                    .font(.system(size: PickerFontSize.label))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            } else {
                Text("⚠️ Select DB")
                    .font(.system(size: PickerFontSize.label))
                    .foregroundColor(.secondary)
                    .opacity(opacity)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.down")
                .font(.system(size: PickerFontSize.chevron))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Database Dropdown

    private var databaseDropdownContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if appState.connection.databases.isEmpty {
                Text("No databases")
                    .font(.system(size: PickerFontSize.dropdownItem))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(appState.connection.databases.sorted { $0.name < $1.name }) { database in
                            databaseRow(database)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }

            Divider()
                .padding(.vertical, 4)

            createDatabaseButton
        }
        .padding(.vertical, 8)
        .frame(minWidth: 200)
    }

    private var createDatabaseButton: some View {
        Button {
            showDatabaseDropdown = false
            onCreateDatabase()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle")
                    .font(.system(size: PickerFontSize.dropdownItem))
                Text("Create Database")
                    .font(.system(size: PickerFontSize.dropdownItem))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!appState.connection.isConnected)
    }

    @ViewBuilder
    private func databaseRow(_ database: DatabaseInfo) -> some View {
        let isSelected = appState.connection.selectedDatabase?.id == database.id

        HStack(spacing: 8) {
            Image(systemName: isSelected ? "checkmark" : "")
                .font(.system(size: PickerFontSize.checkmark, weight: .semibold))
                .frame(width: 12)
                .foregroundColor(.accentColor)

            Text(database.name)
                .font(.system(size: PickerFontSize.dropdownItem))
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                showDatabaseDropdown = false
                onDeleteDatabase(database)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: PickerFontSize.deleteIcon))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Delete database")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelectDatabase(database)
            showDatabaseDropdown = false
        }
    }
}

private final class PreviewMetadataService: MetadataServiceProtocol {
    func fetchDatabases() async throws -> [DatabaseInfo] { [] }
    func fetchPrimaryKeyColumns(schema: String, table: String) async throws -> [String] { [] }
    func fetchColumnInfo(schema: String, table: String) async throws -> [ColumnInfo] { [] }
    func fetchAllSchemaMetadata(databaseId: String) async throws -> [String: [TableInfo]] { [:] }
}

private final class PreviewDatabaseService: DatabaseServiceProtocol {
    var isConnected: Bool { true }
    var connectedDatabase: String? { "postgres" }
    var metadataService: MetadataServiceProtocol { PreviewMetadataService() }

    func connect(
        host: String,
        port: Int,
        username: String,
        password: String,
        database: String,
        sslMode: SSLMode
    ) async throws { }
    func disconnect() async { }
    func shutdown() async { }
    func interruptInFlightTableBrowseLoadForSupersession() async { }
    func fetchDatabases() async throws -> [DatabaseInfo] { [] }
    func createDatabase(name: String) async throws { }
    func deleteDatabase(name: String) async throws { }
    func fetchTables(database: String) async throws -> [TableInfo] { [] }
    func fetchSchemas(database: String) async throws -> [String] { [] }
    func deleteTable(schema: String, table: String) async throws { }
    func truncateTable(schema: String, table: String) async throws { }
    func generateDDL(schema: String, table: String) async throws -> String { "" }
    func fetchAllTableData(schema: String, table: String) async throws -> ([TableRow], [String]) { ([], []) }
    func executeQuery(_ sql: String) async throws -> ([TableRow], [String]) { ([], []) }
    func executeDisplayQuery(_ sql: String) async throws -> ([TableRow], [String]) { ([], []) }
    func deleteRows(
        schema: String,
        table: String,
        primaryKeyColumns: [String],
        rows: [TableRow]
    ) async throws { }
    func updateRow(
        schema: String,
        table: String,
        primaryKeyColumns: [String],
        originalRow: TableRow,
        updatedValues: [String: RowEditValue]
    ) async throws { }
    func fetchPrimaryKeyColumns(schema: String, table: String) async throws -> [String] { [] }
    func fetchColumnInfo(schema: String, table: String) async throws -> [ColumnInfo] { [] }
}

private struct ConnectionDatabasePickerPreview: View {
    @State private var showConnectionDropdown = false
    @State private var showDatabaseDropdown = true

    private let appState = AppState(connection: ConnectionState(databaseService: PreviewDatabaseService()))
    private let connections: [ConnectionProfile] = [
        ConnectionProfile(name: "Local Postgres", host: "localhost", username: "postgres"),
        ConnectionProfile(name: "Analytics", host: "analytics.internal", username: "reporting")
    ]

    var body: some View {
        appState.connection.currentConnection = connections.first
        appState.connection.databases = [
            DatabaseInfo(name: "postgres", tableCount: 42),
            DatabaseInfo(name: "analytics", tableCount: 18),
            DatabaseInfo(name: "staging", tableCount: 12)
        ]
        appState.connection.selectedDatabase = appState.connection.databases.first

        return ConnectionDatabasePicker(
            showConnectionDropdown: $showConnectionDropdown,
            connections: connections,
            onSelectConnection: { _ in },
            onEditConnection: { _ in },
            onDeleteConnection: { _ in },
            onCreateConnection: { },
            showDatabaseDropdown: $showDatabaseDropdown,
            onSelectDatabase: { _ in },
            onDeleteDatabase: { _ in },
            onCreateDatabase: { }
        )
        .environment(appState)
        .frame(width: 420)
        .padding()
    }
}

#Preview("Database Dropdown") {
    ConnectionDatabasePickerPreview()
}
