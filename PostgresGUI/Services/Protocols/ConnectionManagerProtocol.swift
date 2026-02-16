//
//  ConnectionManagerProtocol.swift
//  PostgresGUI
//
//  Protocol abstraction for database connection management
//  Enables dependency injection and testability for DatabaseService
//

import Foundation

/// Abstract TLS mode for database connections
/// Library-agnostic representation of SSL/TLS settings
enum DatabaseTLSMode: Sendable {
    /// No TLS encryption
    case disable
    /// Require TLS but don't verify certificate
    case require
    /// Require TLS and verify CA (but not hostname)
    case verifyCA
    /// Require TLS with full certificate verification including hostname
    case verifyFull
}

/// Protocol defining connection manager operations
/// Implemented by PostgresConnectionManager for production and MockConnectionManager for testing
protocol ConnectionManagerProtocol: Actor {
    /// Check if currently connected to a database
    var isConnected: Bool { get async }

    /// Connect to PostgreSQL database
    /// - Parameters:
    ///   - host: Database host
    ///   - port: Database port
    ///   - username: Username for authentication
    ///   - password: Password for authentication
    ///   - database: Database name to connect to
    ///   - tlsMode: TLS mode for encrypted connections
    /// - Throws: ConnectionError if connection fails
    func connect(
        host: String,
        port: Int,
        username: String,
        password: String,
        database: String,
        tlsMode: DatabaseTLSMode
    ) async throws

    /// Disconnect from database (keeps resources like EventLoopGroup for reuse)
    func disconnect() async

    /// Full shutdown including all resources - call on app termination
    func shutdown() async

    /// Interrupt in-flight operation work for supersession.
    /// Implementations should invalidate stale work and force fresh reconnect on next operation.
    func interruptInFlightOperationForSupersession() async

    /// Reconnect to a specific database using the last successful credentials.
    /// - Parameter database: Target database name for the new connection.
    /// - Throws: ConnectionError.notConnected when no prior credentials are available.
    func reconnectUsingStoredCredentials(database: String) async throws

    /// Execute an operation with the active connection
    /// - Parameter operation: Async closure that receives the abstract DatabaseConnectionProtocol
    /// - Returns: Result of the operation
    /// - Throws: ConnectionError.notConnected if not connected, or operation errors
    func withConnection<T>(_ operation: @escaping (DatabaseConnectionProtocol) async throws -> T) async throws -> T

    /// Test connection without maintaining it
    /// - Parameters:
    ///   - host: Database host
    ///   - port: Database port
    ///   - username: Username
    ///   - password: Password
    ///   - database: Database name
    ///   - tlsMode: TLS mode for encrypted connections
    /// - Returns: True if connection succeeds
    /// - Throws: ConnectionError if connection fails
    static func testConnection(
        host: String,
        port: Int,
        username: String,
        password: String,
        database: String,
        tlsMode: DatabaseTLSMode
    ) async throws -> Bool
}
