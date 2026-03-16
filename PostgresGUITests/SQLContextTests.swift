//
//  SQLContextTests.swift
//  PostgresGUITests
//
//  Unit tests for SQLContext enum
//

import Testing
@testable import PostgresGUI

@Suite("SQLContext Tests")
struct SQLContextTests {
    @Test("All context cases exist")
    func contextCasesExist() {
        let contexts: [SQLContext] = [
            .selectClause,
            .fromClause,
            .whereClause,
            .tableReference,
            .defaultContext
        ]
        #expect(contexts.count == 5)
    }

    @Test("Context conforms to Equatable")
    func contextIsEquatable() {
        let context1: SQLContext = .selectClause
        let context2: SQLContext = .selectClause
        let context3: SQLContext = .fromClause
        #expect(context1 == context2)
        #expect(context1 != context3)
    }

    @Test("Context conforms to Hashable")
    func contextIsHashable() {
        let context1: SQLContext = .selectClause
        let context2: SQLContext = .selectClause
        #expect(context1.hashValue == context2.hashValue)
    }
}
