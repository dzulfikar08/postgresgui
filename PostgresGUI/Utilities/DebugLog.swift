//
//  DebugLog.swift
//  PostgresGUI
//
//  Conditional logging utility that only logs in Debug builds
//

import Logging

/// Utility for conditional debug logging
/// All logs are suppressed in Release builds for performance and privacy
enum DebugLog {
#if DEBUG
    private static var isLoggingConfigured = false

    static func configureLogging() {
        guard !isLoggingConfigured else { return }
        isLoggingConfigured = true

        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardOutput(label: label)
            handler.logLevel = .debug
            return handler
        }
    }

#endif
    
    /// Print a message only in Debug builds
    /// - Parameter items: Items to print (same signature as Swift's print)
    static func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
        #if DEBUG
        Swift.print(items.map { "\($0)" }.joined(separator: separator), terminator: terminator)
        #endif
    }
}

/// Extension to configure Logger instances for conditional logging
extension Logger {
    /// Create a logger that respects build configuration
    /// In Release builds, the logger will be configured to suppress most logs
    /// - Parameter label: Logger label
    /// - Returns: Configured Logger instance
    nonisolated static func debugLogger(label: String) -> Logger {
        #if DEBUG
        return Logger(label: label)
        #else
        // In Release builds, create a logger with critical log level
        // This suppresses info, debug, trace, and notice logs
        var logger = Logger(label: label)
        logger.logLevel = .critical
        return logger
        #endif
    }
}
