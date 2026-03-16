//
//  SyntaxHighlightedEditor.swift
//  PostgresGUI
//
//  Created by ghazi on 11/29/25.
//

import SwiftUI
import AppKit

// MARK: - SQL Syntax Highlighter

/// Handles SQL syntax highlighting with regex-based pattern matching
private struct SQLSyntaxHighlighter {

    static let maxHighlightingLength = 50_000

    // Compiled regex patterns (created once)
    let patterns: Patterns

    struct Patterns {
        let keyword: NSRegularExpression
        let string: NSRegularExpression
        let number: NSRegularExpression
        let singleLineComment: NSRegularExpression
        let multiLineComment: NSRegularExpression
        let `operator`: NSRegularExpression
        let function: NSRegularExpression

        init() {
            do {
                keyword = try NSRegularExpression(
                    pattern: "\\b(SELECT|FROM|WHERE|JOIN|INNER|LEFT|RIGHT|FULL|OUTER|ON|AS|ORDER|BY|GROUP|HAVING|INSERT|UPDATE|DELETE|CREATE|ALTER|DROP|TABLE|INDEX|VIEW|DATABASE|SCHEMA|UNION|INTERSECT|EXCEPT|DISTINCT|LIMIT|OFFSET|CASE|WHEN|THEN|ELSE|END|IF|EXISTS|NULL|NOT|AND|OR|IN|LIKE|ILIKE|SIMILAR|TO|BETWEEN|IS|CAST|COALESCE|NULLIF|GREATEST|LEAST|EXTRACT|DATE_PART|NOW|CURRENT_DATE|CURRENT_TIME|CURRENT_TIMESTAMP|TRUE|FALSE|BOOLEAN|INTEGER|BIGINT|SMALLINT|DECIMAL|NUMERIC|REAL|DOUBLE|PRECISION|CHAR|VARCHAR|TEXT|BYTEA|DATE|TIME|TIMESTAMP|INTERVAL|ARRAY|JSON|JSONB|UUID|SERIAL|BIGSERIAL|PRIMARY|KEY|FOREIGN|REFERENCES|UNIQUE|CHECK|DEFAULT|CONSTRAINT|USING|WITH|WITHOUT|OIDS|TABLESPACE|STORAGE|PARAMETER|SET|RESET|SHOW|GRANT|REVOKE|EXPLAIN|ANALYZE|VACUUM|REINDEX|CLUSTER|TRUNCATE|BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE|TRANSACTION|ISOLATION|LEVEL|READ|WRITE|ONLY|UNCOMMITTED|COMMITTED|REPEATABLE|SERIALIZABLE|LOCK|FOR|UPDATE|SHARE|NOWAIT|SKIP|LOCKED|RETURNING|RETURNS|LANGUAGE|PLPGSQL|FUNCTION|PROCEDURE|TRIGGER|SEQUENCE|TYPE|DOMAIN|ENUM|AGGREGATE|OPERATOR|OPERATOR\\s+CLASS|OPERATOR\\s+FAMILY|RULE|POLICY|EXTENSION|COLLATION|CONVERSION|TEXT\\s+SEARCH|CONFIGURATION|DICTIONARY|PARSER|TEMPLATE|ROLE|USER|GROUP|PASSWORD|SUPERUSER|CREATEDB|CREATEROLE|INHERIT|LOGIN|REPLICATION|BYPASSRLS|CONNECTION\\s+LIMIT|VALID|UNTIL|IN\\s+SCHEMA|PUBLIC|CURRENT_SCHEMA|SEARCH_PATH)\\b",
                    options: [.caseInsensitive]
                )
                string = try NSRegularExpression(pattern: "'(?:[^'\\\\]|\\\\.)*'", options: [])
                number = try NSRegularExpression(pattern: "\\b\\d+\\.?\\d*\\b", options: [])
                singleLineComment = try NSRegularExpression(pattern: "--.*", options: [])
                multiLineComment = try NSRegularExpression(pattern: "/\\*[\\s\\S]*?\\*/", options: [.dotMatchesLineSeparators])
                `operator` = try NSRegularExpression(pattern: "::|->>|->|@>|<@|\\?\\||\\?&|\\?|<=|>=|<>|!=|[=<>!+\\-*/%&|^~]", options: [])
                function = try NSRegularExpression(pattern: "\\b[A-Za-z_][A-Za-z0-9_]*\\s*\\(", options: [])
            } catch {
                fatalError("Failed to compile regex patterns: \(error)")
            }
        }
    }

    struct Colors {
        let keyword: NSColor
        let string: NSColor
        let number: NSColor
        let comment: NSColor
        let `operator`: NSColor
        let function: NSColor
        let `default`: NSColor

        init(isDark: Bool) {
            if isDark {
                keyword = .systemBlue
                string = .systemGreen
                number = .systemOrange
                comment = .systemGray
                `operator` = .systemPink
                function = .systemCyan
            } else {
                keyword = NSColor(red: 0.0, green: 0.0, blue: 0.8, alpha: 1.0)
                string = NSColor(red: 0.0, green: 0.6, blue: 0.0, alpha: 1.0)
                number = NSColor(red: 0.8, green: 0.4, blue: 0.0, alpha: 1.0)
                comment = NSColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
                `operator` = NSColor(red: 0.8, green: 0.0, blue: 0.4, alpha: 1.0)
                function = NSColor(red: 0.0, green: 0.5, blue: 0.8, alpha: 1.0)
            }
            `default` = .textColor
        }
    }

    init() {
        self.patterns = Patterns()
    }

    /// Apply syntax highlighting to text storage (incremental, for user typing)
    func highlightIncremental(_ textStorage: NSTextStorage, isDark: Bool) {
        let text = textStorage.string
        guard !text.isEmpty, text.count <= Self.maxHighlightingLength else { return }

        let colors = Colors(isDark: isDark)
        let fullRange = NSRange(location: 0, length: text.utf16.count)
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

        textStorage.beginEditing()
        textStorage.addAttribute(.font, value: font, range: fullRange)
        textStorage.addAttribute(.foregroundColor, value: colors.default, range: fullRange)
        applyPatterns(to: text, colors: colors) { range, color in
            textStorage.addAttribute(.foregroundColor, value: color, range: range)
        }
        textStorage.endEditing()
    }

    /// Apply syntax highlighting and return attributed string (for external text updates)
    func highlight(_ text: String, isDark: Bool) -> NSAttributedString? {
        guard !text.isEmpty, text.count <= Self.maxHighlightingLength else { return nil }

        let colors = Colors(isDark: isDark)
        let attributed = NSMutableAttributedString(string: text)
        let fullRange = NSRange(location: 0, length: text.utf16.count)
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

        attributed.addAttribute(.font, value: font, range: fullRange)
        attributed.addAttribute(.foregroundColor, value: colors.default, range: fullRange)
        applyPatterns(to: text, colors: colors) { range, color in
            attributed.addAttribute(.foregroundColor, value: color, range: range)
        }

        return attributed
    }

    /// Core pattern matching logic - shared between both highlighting methods
    private func applyPatterns(to text: String, colors: Colors, apply: (NSRange, NSColor) -> Void) {
        let fullRange = NSRange(location: 0, length: text.utf16.count)
        var protected = IndexSet()

        func isProtected(_ range: NSRange) -> Bool {
            range.length > 0 && protected.contains(integersIn: range.location..<(range.location + range.length))
        }

        func protect(_ range: NSRange) {
            if range.length > 0 {
                protected.insert(integersIn: range.location..<(range.location + range.length))
            }
        }

        // Order matters: comments > strings > numbers/keywords/functions/operators
        let orderedPatterns: [(NSRegularExpression, NSColor, Bool)] = [
            (patterns.multiLineComment, colors.comment, true),
            (patterns.singleLineComment, colors.comment, true),
            (patterns.string, colors.string, true),
            (patterns.number, colors.number, false),
            (patterns.keyword, colors.keyword, false),
            (patterns.function, colors.function, false),
            (patterns.operator, colors.operator, false),
        ]

        for (pattern, color, shouldProtect) in orderedPatterns {
            pattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                var range = match.range

                // For functions, exclude the opening paren
                if pattern === patterns.function {
                    range = NSRange(location: range.location, length: range.length - 1)
                }

                if !isProtected(range) {
                    apply(range, color)
                    if shouldProtect { protect(range) }
                }
            }
        }
    }
}

// MARK: - Syntax Highlighted Editor

struct SyntaxHighlightedEditor: NSViewRepresentable {
    @Binding var text: String
    @Environment(\.colorScheme) var colorScheme
    let completionService: SQLCompletionServiceProtocol?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()

        // Configure text view
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]

        // Disable automatic text substitutions for code editing
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false

        // Set up scroll view
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = textView

        // Line numbers
        scrollView.rulersVisible = true
        scrollView.hasVerticalRuler = true
        let lineNumberRuler = LineNumberRulerView(scrollView: scrollView, textView: textView)
        scrollView.verticalRulerView = lineNumberRuler

        // Set delegate and store references
        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        context.coordinator.lineNumberRuler = lineNumberRuler

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        let isDark = colorScheme == .dark
        let colorSchemeChanged = context.coordinator.lastIsDark != isDark
        context.coordinator.lastIsDark = isDark

        if textView.string != text && !context.coordinator.isUpdatingFromUserInput {
            let selectedRange = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(selectedRange)
            context.coordinator.applyHighlighting(to: textView, isDark: isDark)
            context.coordinator.lineNumberRuler?.needsDisplay = true
        } else if colorSchemeChanged {
            context.coordinator.applyHighlighting(to: textView, isDark: isDark)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self, completionService: completionService)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        private let parent: SyntaxHighlightedEditor
        private let highlighter = SQLSyntaxHighlighter()
        private var highlightingWorkItem: DispatchWorkItem?

        // Completion support
        private let completionService: SQLCompletionServiceProtocol?
        private var completionTimer: DispatchWorkItem?
        private var currentCompletions: [CompletionSuggestion] = []
        private var manualTriggerRequested = false

        weak var textView: NSTextView?
        weak var lineNumberRuler: LineNumberRulerView?
        var isUpdatingFromUserInput = false
        var lastIsDark = false

        init(parent: SyntaxHighlightedEditor, completionService: SQLCompletionServiceProtocol? = nil) {
            self.parent = parent
            self.completionService = completionService
            self.lastIsDark = parent.colorScheme == .dark
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = textView else { return }

            isUpdatingFromUserInput = true
            parent.text = textView.string
            lineNumberRuler?.needsDisplay = true

            // Debounce completion
            completionTimer?.cancel()

            // Schedule new completion trigger
            if let service = completionService {
                let workItem = DispatchWorkItem { [weak self] in
                    self?.triggerCompletion()
                }
                completionTimer = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
            }

            // Debounce highlighting
            highlightingWorkItem?.cancel()
            let isDark = lastIsDark
            let workItem = DispatchWorkItem { [weak self] in
                guard let self, let textView = self.textView, let storage = textView.textStorage else { return }
                self.highlighter.highlightIncremental(storage, isDark: isDark)
                self.isUpdatingFromUserInput = false
            }
            highlightingWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
        }

        func applyHighlighting(to textView: NSTextView, isDark: Bool) {
            guard let attributed = highlighter.highlight(textView.string, isDark: isDark),
                  let textStorage = textView.textStorage else { return }

            let selectedRange = textView.selectedRange()
            let wasFirstResponder = textView.window?.firstResponder === textView

            textStorage.beginEditing()
            textStorage.setAttributedString(attributed)
            textStorage.endEditing()

            // Restore selection
            let maxLocation = textView.string.utf16.count
            let validLocation = min(selectedRange.location, maxLocation)
            let validLength = min(selectedRange.length, maxLocation - validLocation)

            DispatchQueue.main.async {
                textView.setSelectedRange(NSRange(location: validLocation, length: validLength))
                if wasFirstResponder {
                    textView.window?.makeFirstResponder(textView)
                }
            }
        }

        // MARK: - Completion Support

        func triggerCompletionManually() {
            manualTriggerRequested = true
            triggerCompletion()
            manualTriggerRequested = false
        }

        private func triggerCompletion() {
            guard let textView = textView,
                  let service = completionService else { return }

            // Get current cursor position
            let selectedRange = textView.selectedRange()
            guard selectedRange.length == 0 else { return } // Only trigger when not selecting text

            // Get partial word at cursor
            let text = textView.string as NSString
            let partialWord = getPartialWord(at: selectedRange.location, in: text)

            // Trigger immediately if manually requested, otherwise require 2+ characters
            guard manualTriggerRequested || partialWord.count >= 2 else { return }

            // Detect context
            let context = service.detectContext(at: selectedRange, inText: text as String)

            // Get completions
            let suggestions = service.getCompletions(for: partialWord, inContext: context)

            guard !suggestions.isEmpty else { return }

            // Store completions for delegate method
            self.currentCompletions = suggestions

            // Trigger NSTextView's completion UI
            textView.complete(nil)
        }

        private func getPartialWord(at location: Int, in text: NSString) -> String {
            var start = location
            while start > 0 {
                let char = text.character(at: start - 1)
                if char == 32 || char == 40 || char == 41 || char == 44 || char == 46 { // space, (, ), ,, .
                    break
                }
                start -= 1
            }

            return text.substring(with: NSRange(location: start, length: location - start))
        }

        // NSTextViewDelegate method for completions
        // TODO: Fix optionality to match NSTextViewDelegate protocol
        // func textView(_ textView: NSTextView, completions: [String]?, forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String]? {
        //     guard completionService != nil else { return [] }
        //     return currentCompletions.map { $0.text }
        // }
    }
}
