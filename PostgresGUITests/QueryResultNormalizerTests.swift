//
//  QueryResultNormalizerTests.swift
//  PostgresGUITests
//

import Testing
@testable import PostgresGUI

@Suite("QueryResultNormalizer")
struct QueryResultNormalizerTests {
    @Test func expandsJsonRowsIntoColumns() {
        let rows = [
            TableRow(values: ["row": #"{"id":1,"name":"Widget"}"#]),
            TableRow(values: ["row": #"{"id":2,"price":19.99}"#])
        ]

        let (normalizedRows, normalizedColumns) = QueryResultNormalizer.normalizeDisplayRows(
            rows: rows,
            columnNames: ["row"]
        )

        #expect(normalizedColumns == ["id", "name", "price"])
        #expect(normalizedRows.count == 2)
        #expect(normalizedRows[0].values["id"] == "1")
        #expect(normalizedRows[0].values["name"] == "Widget")
        #expect(normalizedRows[0].values["price"] == nil)
        #expect(normalizedRows[1].values["id"] == "2")
        #expect(normalizedRows[1].values["price"] == "19.99")
    }

    @Test func fallsBackWhenJsonParseFails() {
        let rows = [
            TableRow(values: ["row": #"{"id":1}"#]),
            TableRow(values: ["row": "not-json"])
        ]

        let (normalizedRows, normalizedColumns) = QueryResultNormalizer.normalizeDisplayRows(
            rows: rows,
            columnNames: ["row"]
        )

        #expect(normalizedColumns == ["row"])
        #expect(normalizedRows.count == 2)
        #expect(normalizedRows[0].values["row"] == #"{"id":1}"#)
        #expect(normalizedRows[1].values["row"] == "not-json")
    }
}
