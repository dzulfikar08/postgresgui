//
//  QueryResultNormalizer.swift
//  PostgresGUI
//
//  Normalizes display results for safe rendering.
//

import Foundation

struct QueryResultNormalizer {
    static func normalizeDisplayRows(
        rows: [TableRow],
        columnNames: [String],
        preferredColumnOrder: [String]? = nil
    ) -> ([TableRow], [String]) {
        guard columnNames == ["row"], !rows.isEmpty else {
            return (rows, columnNames)
        }

        var expandedRows: [TableRow] = []
        var allKeys = Set<String>()
        var rawOrder: [String] = []
        var seenKeys = Set<String>()

        for row in rows {
            guard let jsonText = row.values["row"] ?? nil,
                  let parsed = parseJSONObject(jsonText) else {
                return (rows, columnNames)
            }

            for key in parsed.keys where !seenKeys.contains(key) {
                seenKeys.insert(key)
                rawOrder.append(key)
            }
            allKeys.formUnion(parsed.keys)
            expandedRows.append(TableRow(id: row.id, values: parsed))
        }

        if let preferredColumnOrder, !preferredColumnOrder.isEmpty {
            var ordered: [String] = []
            ordered.reserveCapacity(allKeys.count)
            var preferredSet = Set<String>()

            for name in preferredColumnOrder where allKeys.contains(name) {
                ordered.append(name)
                preferredSet.insert(name)
            }

            if ordered.count < allKeys.count {
                for key in rawOrder where !preferredSet.contains(key) && allKeys.contains(key) {
                    ordered.append(key)
                }
            }

            return (expandedRows, ordered)
        }

        return (expandedRows, rawOrder)
    }

    private static func parseJSONObject(_ jsonText: String) -> [String: String?]? {
        guard let data = jsonText.data(using: .utf8) else {
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: data),
              let object = json as? [String: Any] else {
            return nil
        }

        var result: [String: String?] = [:]
        for (key, value) in object {
            result[key] = stringifyJSONValue(value)
        }
        return result
    }

    private static func stringifyJSONValue(_ value: Any) -> String? {
        if value is NSNull {
            return nil
        }

        if let stringValue = value as? String {
            return stringValue
        }

        if let numberValue = value as? NSNumber {
            return numberValue.stringValue
        }

        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let jsonString = String(data: data, encoding: .utf8) {
            return jsonString
        }

        return String(describing: value)
    }
}
