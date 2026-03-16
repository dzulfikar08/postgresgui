import Testing
@testable import PostgresGUI

@Suite("SQLTokenizer Tests")
struct SQLTokenizerTests {
    var tokenizer: SQLTokenizer

    init() {
        tokenizer = SQLTokenizer()
    }

    @Test("Tokenize simple SELECT statement")
    func tokenizeSimpleSelect() {
        let tokens = tokenizer.tokenize("SELECT * FROM users")
        #expect(tokens.contains(.keyword("SELECT")))
        #expect(tokens.contains(.identifier("*")))
        #expect(tokens.contains(.keyword("FROM")))
        #expect(tokens.contains(.identifier("users")))
    }

    @Test("Tokenize with whitespace")
    func tokenizeWithWhitespace() {
        let tokens = tokenizer.tokenize("SELECT   id")
        #expect(tokens.contains(.keyword("SELECT")))
        #expect(tokens.contains(.whitespace))
        #expect(tokens.contains(.identifier("id")))
    }

    @Test("Tokenize string literal")
    func tokenizeStringLiteral() {
        let tokens = tokenizer.tokenize("WHERE name = 'test'")
        #expect(tokens.contains(.stringLiteral("'test'")))
    }

    @Test("Detect context in SELECT clause")
    func detectContextInSelectClause() {
        // "SELECT id FRO" - cursor at position 9 (after "FRO")
        let sql = "SELECT id FRO"
        let context = tokenizer.getContext(at: NSRange(location: 9, length: 0), inText: sql)
        #expect(context == .selectClause)
    }

    @Test("Detect context in FROM clause")
    func detectContextInFromClause() {
        // "FROM use" - cursor at position 7 (after "use")
        let sql = "FROM use"
        let context = tokenizer.getContext(at: NSRange(location: 7, length: 0), inText: sql)
        #expect(context == .fromClause)
    }

    @Test("Detect context in WHERE clause")
    func detectContextInWhereClause() {
        // "WHERE id =" - cursor at position 9 (after "=")
        let sql = "WHERE id ="
        let context = tokenizer.getContext(at: NSRange(location: 9, length: 0), inText: sql)
        #expect(context == .whereClause)
    }

    @Test("Detect default context when no keywords")
    func detectDefaultContext() {
        let sql = "just text"
        let context = tokenizer.getContext(at: NSRange(location: 5, length: 0), inText: sql)
        #expect(context == .defaultContext)
    }
}
