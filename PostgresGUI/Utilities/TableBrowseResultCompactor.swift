//
//  TableBrowseResultCompactor.swift
//  PostgresGUI
//
//  Compacts very large table-browse cell payloads off the main actor.
//

import Foundation

enum TableBrowseResultCompactor {
    static func compactRowsOffMain(
        rows: [TableRow],
        maxCellCharacters: Int,
        truncationSuffix: String
    ) async -> [TableRow] {
        guard !rows.isEmpty else { return rows }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(
                    returning: compactRows(
                        rows: rows,
                        maxCellCharacters: maxCellCharacters,
                        truncationSuffix: truncationSuffix
                    )
                )
            }
        }
    }

    private static func compactRows(
        rows: [TableRow],
        maxCellCharacters: Int,
        truncationSuffix: String
    ) -> [TableRow] {
        rows.map { row in
            var compactedValues: [String: String?] = [:]
            compactedValues.reserveCapacity(row.values.count)

            for (column, value) in row.values {
                compactedValues[column] = compactValue(
                    value,
                    maxCellCharacters: maxCellCharacters,
                    truncationSuffix: truncationSuffix
                )
            }

            return TableRow(id: row.id, values: compactedValues)
        }
    }

    private static func compactValue(
        _ value: String?,
        maxCellCharacters: Int,
        truncationSuffix: String
    ) -> String? {
        guard let value else { return nil }
        guard maxCellCharacters > 0 else { return truncationSuffix }
        guard value.count > maxCellCharacters else { return value }

        let suffixLength = truncationSuffix.count
        guard maxCellCharacters > suffixLength else {
            return String(truncationSuffix.prefix(maxCellCharacters))
        }

        let prefixLength = maxCellCharacters - suffixLength
        return String(value.prefix(prefixLength)) + truncationSuffix
    }
}
