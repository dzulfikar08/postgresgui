//
//  SQLTokenTests.swift
//  PostgresGUITests
//
//  Unit tests for SQLToken enum
//

import Testing
@testable import PostgresGUI

@Suite("SQLToken Tests")
struct SQLTokenTests {
    @Test("Keyword token creation")
    func keywordToken() {
        let token = SQLToken.keyword("SELECT")
        if case .keyword(let value) = token {
            #expect(value == "SELECT")
        } else {
            Issue.record("Expected keyword token")
        }
    }

    @Test("Identifier token creation")
    func identifierToken() {
        let token = SQLToken.identifier("username")
        if case .identifier(let value) = token {
            #expect(value == "username")
        } else {
            Issue.record("Expected identifier token")
        }
    }

    @Test("Operator token creation")
    func operatorToken() {
        let token = SQLToken.`operator`("=")
        if case .`operator`(let value) = token {
            #expect(value == "=")
        } else {
            Issue.record("Expected operator token")
        }
    }

    @Test("All token types exist")
    func testAllTokenTypes() {
        let tokens: [SQLToken] = [
            .keyword("SELECT"),
            .identifier("users"),
            .operator("="),
            .stringLiteral("test"),
            .whitespace,
            .dot,
            .comma
        ]
        #expect(tokens.count == 7)
    }

    @Test("Token conforms to Equatable")
    func tokenEquality() {
        let token1 = SQLToken.keyword("SELECT")
        let token2 = SQLToken.keyword("SELECT")
        let token3 = SQLToken.keyword("FROM")
        #expect(token1 == token2)
        #expect(token1 != token3)
    }

    @Test("String literal token")
    func stringLiteralToken() {
        let token = SQLToken.stringLiteral("'test value'")
        if case .stringLiteral(let value) = token {
            #expect(value == "'test value'")
        } else {
            Issue.record("Expected string literal token")
        }
    }
}
