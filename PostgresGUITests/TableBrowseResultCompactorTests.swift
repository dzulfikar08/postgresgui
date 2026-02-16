//
//  TableBrowseResultCompactorTests.swift
//  PostgresGUITests
//

import Foundation
import Testing
@testable import PostgresGUI

@Suite("TableBrowseResultCompactor")
struct TableBrowseResultCompactorTests {

    @Test func longValue_isCompactedWithSuffix() async {
        let source = String(repeating: "a", count: Constants.tableBrowseMaxCellCharacters + 300)
        let rows = [TableRow(values: ["payload": source])]

        let compacted = await TableBrowseResultCompactor.compactRowsOffMain(
            rows: rows,
            maxCellCharacters: Constants.tableBrowseMaxCellCharacters,
            truncationSuffix: Constants.tableBrowseTruncationSuffix
        )

        let compactedValue = compacted.first?.values["payload"] ?? nil
        #expect(compactedValue != nil)
        #expect(compactedValue?.hasSuffix(Constants.tableBrowseTruncationSuffix) == true)
        #expect(compactedValue?.count == Constants.tableBrowseMaxCellCharacters)
    }

    @Test func shortValue_isUnchanged() async {
        let source = "short"
        let rows = [TableRow(values: ["payload": source])]

        let compacted = await TableBrowseResultCompactor.compactRowsOffMain(
            rows: rows,
            maxCellCharacters: Constants.tableBrowseMaxCellCharacters,
            truncationSuffix: Constants.tableBrowseTruncationSuffix
        )

        #expect((compacted.first?.values["payload"] ?? nil) == source)
    }

    @Test func nilValue_isPreserved() async {
        let rows = [TableRow(values: ["payload": nil])]

        let compacted = await TableBrowseResultCompactor.compactRowsOffMain(
            rows: rows,
            maxCellCharacters: Constants.tableBrowseMaxCellCharacters,
            truncationSuffix: Constants.tableBrowseTruncationSuffix
        )

        let value = compacted.first?.values["payload"] ?? nil
        #expect(value == nil)
    }
}
