//
//  SQLTokenizer.swift
//  PostgresGUI
//
//  Simple SQL lexer for tokenization and context detection
//

import Foundation

/// Simple SQL tokenizer for parsing queries
struct SQLTokenizer {

    /// SQL keywords that signal context
    private let contextKeywords: Set<String> = [
        "SELECT", "FROM", "WHERE", "JOIN", "INNER", "LEFT", "RIGHT",
        "INSERT", "UPDATE", "DELETE", "CREATE", "ALTER", "DROP"
    ]

    /// Tokenize a line of SQL text
    func tokenize(_ line: String) -> [SQLToken] {
        var tokens: [SQLToken] = []
        var current = line.startIndex
        let keywords = contextKeywords

        while current < line.endIndex {
            let remaining = line[current...]

            // Skip whitespace
            if remaining.first?.isWhitespace == true {
                tokens.append(.whitespace)
                current = line.index(after: current)
                continue
            }

            // String literal
            if remaining.first == "'" {
                if let end = remaining.dropFirst().firstIndex(of: "'") {
                    let strEnd = line.index(after: end)
                    let literal = String(line[current..<strEnd])
                    tokens.append(.stringLiteral(literal))
                    current = strEnd
                    continue
                }
            }

            // Dot operator
            if remaining.first == "." {
                tokens.append(.dot)
                current = line.index(after: current)
                continue
            }

            // Comma
            if remaining.first == "," {
                tokens.append(.comma)
                current = line.index(after: current)
                continue
            }

            // Operator
            if let opEnd = findOperatorEnd(in: remaining) {
                let op = String(line[current..<opEnd])
                tokens.append(.operator(op))
                current = opEnd
                continue
            }

            // Word (keyword or identifier)
            if let wordEnd = remaining.firstIndex(where: { $0.isWhitespace || $0 == "." || $0 == "," || $0 == "=" || $0 == "'" || $0 == "(" || $0 == ")" }) {
                let word = String(line[current..<wordEnd]).uppercased()
                if keywords.contains(word) {
                    tokens.append(.keyword(word))
                } else {
                    tokens.append(.identifier(String(line[current..<wordEnd])))
                }
                current = wordEnd
            } else {
                // Last word
                let word = String(line[current...]).uppercased()
                if keywords.contains(word) {
                    tokens.append(.keyword(word))
                } else {
                    tokens.append(.identifier(String(line[current...])))
                }
                break
            }
        }

        return tokens
    }

    /// Detect SQL context at a given cursor position
    func getContext(at range: NSRange, inText text: String) -> SQLContext {
        let tokens = tokenize(text)

        guard range.location < text.utf16.count else {
            return .defaultContext
        }

        // Find tokens before cursor position
        var currentPos = 0
        var lastKeyword: String? = nil
        var foundSelect = false
        var foundFrom = false

        for token in tokens {
            let tokenLength = tokenLength(token)

            if currentPos + tokenLength > range.location {
                // Cursor is within this token
                break
            }

            switch token {
            case .keyword(let keyword):
                lastKeyword = keyword
                if keyword == "FROM" || keyword == "JOIN" {
                    foundFrom = true
                } else if keyword == "SELECT" {
                    foundSelect = true
                    foundFrom = false
                }
            case .dot:
                // After a dot, we're in table reference context
                if lastKeyword != nil {
                    return .tableReference
                }
            default:
                break
            }

            currentPos += tokenLength
        }

        // Determine context based on last keyword
        if let keyword = lastKeyword {
            if keyword == "FROM" || keyword == "JOIN" {
                return .fromClause
            } else if keyword == "WHERE" {
                return .whereClause
            } else if foundSelect && !foundFrom {
                return .selectClause
            }
        }

        return .defaultContext
    }

    // MARK: - Private Helpers

    private func tokenLength(_ token: SQLToken) -> Int {
        switch token {
        case .keyword(let s), .identifier(let s), .operator(let s), .stringLiteral(let s):
            return s.utf16.count
        case .whitespace:
            return 1
        case .dot, .comma:
            return 1
        }
    }

    private func findOperatorEnd(in string: Substring) -> Substring.Index? {
        let operators = ["<>", "<=", ">=", "!=", "=", "<", ">", "LIKE", "ILIKE", "IN", "IS", "AND", "OR"]

        for op in operators {
            if string.starts(with: op) {
                return string.index(string.startIndex, offsetBy: op.count)
            }
        }
        return nil
    }
}
