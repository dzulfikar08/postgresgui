//
//  PostgresConnectionManager.swift
//  PostgresGUI
//
//  Manages PostgresNIO connection lifecycle and EventLoopGroup
//

import Foundation
import PostgresNIO
import NIOCore
import NIOPosix
import NIOSSL
import Logging

/// Actor-isolated manager for PostgresNIO connections
/// Handles connection lifecycle, EventLoopGroup management, and async/await bridging
actor PostgresConnectionManager: ConnectionManagerProtocol {

    // MARK: - Connection Parameters Storage

    /// Stored connection parameters for reconnection
    private struct ConnectionParams {
        let host: String
        let port: Int
        let username: String
        let password: String
        let database: String
        let tlsMode: DatabaseTLSMode
    }

    // MARK: - Properties

    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    private var connection: PostgresConnection?
    private var wrappedConnection: PostgresDatabaseConnection?
    private var storedParams: ConnectionParams?
    private let logger = Logger.debugLogger(label: "com.postgresgui.connection")

    /// Generation counter to detect stale connection attempts
    /// When a new connect() is called, the generation increments.
    /// When an older connect() completes, it checks if it's still current.
    private var connectionGeneration: UInt64 = 0

    /// Check if currently connected
    var isConnected: Bool {
        connection != nil
    }

    // MARK: - Initialization

    init() {
        logger.info("PostgresConnectionManager initialized")
    }

    deinit {
        let conn = connection
        let elg = eventLoopGroup
        let logger = self.logger

        if conn != nil || elg != nil {
            logger.warning("⚠️ PostgresConnectionManager deinit with active resources - cleanup should have been explicit!")

            // Fallback cleanup (fire-and-forget)
            // This should rarely run if explicit cleanup is working
            Task.detached {
                if let conn = conn {
                    logger.debug("Closing connection in deinit (fallback)")
                    try? await conn.close()
                }

                if let elg = elg {
                    logger.debug("Shutting down EventLoopGroup in deinit (fallback)")
                    try? await elg.shutdownGracefully()
                }

                logger.info("Fallback cleanup completed")
            }
        } else {
            logger.debug("PostgresConnectionManager deinit - resources already cleaned up ✅")
        }
    }

    // MARK: - Connection Management

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
        tlsMode: DatabaseTLSMode = .disable
    ) async throws {
        logger.info("Connecting to PostgreSQL at \(host):\(port), database: \(database)")

        // Increment generation to invalidate any in-flight connection attempts
        connectionGeneration &+= 1
        let myGeneration = connectionGeneration

        // Close existing connection if any
        if connection != nil {
            await disconnect()
        }

        // Create EventLoopGroup if not exists
        if eventLoopGroup == nil {
            let threadCount = System.coreCount
            logger.debug("Creating EventLoopGroup with \(threadCount) threads")
            eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: threadCount)
            logger.info("✅ EventLoopGroup created successfully")
        }

        guard let elg = eventLoopGroup else {
            throw ConnectionError.unknownError(NSError(domain: "PostgresConnectionManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create EventLoopGroup"]))
        }

        // Build PostgresNIO configuration
        var config = PostgresConnection.Configuration(
            host: host,
            port: port,
            username: username,
            password: password,
            database: database,
            tls: .disable
        )

        // Configure TLS based on mode
        if let tlsConfig = Self.makeTLSConfiguration(for: tlsMode) {
            do {
                let sslContext = try NIOSSLContext(configuration: tlsConfig)
                config.tls = .require(sslContext)
                logger.debug("SSL context created successfully")
            } catch {
                logger.error("Failed to create SSL context: \(error)")
                // FAIL instead of fallback - security requirement
                throw ConnectionError.sslContextCreationFailed(error.localizedDescription)
            }
        }

        do {
            // Connect using PostgresNIO
            logger.debug("Establishing PostgreSQL connection...")
            let newConnection = try await PostgresConnection.connect(
                on: elg.next(),
                configuration: config,
                id: 1,
                logger: logger
            )

            // Check if a newer connect() was called while we were awaiting
            // If so, close this connection immediately - it's stale
            guard connectionGeneration == myGeneration else {
                logger.warning("⚠️ Stale connection detected (generation \(myGeneration) vs current \(connectionGeneration)), closing")
                try? await newConnection.close()
                throw ConnectionError.connectionCancelled
            }

            self.connection = newConnection
            self.wrappedConnection = PostgresDatabaseConnection(connection: newConnection, logger: logger)
            self.storedParams = ConnectionParams(
                host: host,
                port: port,
                username: username,
                password: password,
                database: database,
                tlsMode: tlsMode
            )
            logger.info("Successfully connected to PostgreSQL")
        } catch let error as ConnectionError where error == .connectionCancelled {
            // Re-throw cancellation without shutting down ELG (newer connection needs it)
            throw error
        } catch {
            logger.error("Connection failed: \(error)")
            // Shutdown event loop group on failure
            try? await eventLoopGroup?.shutdownGracefully()
            eventLoopGroup = nil
            throw PostgresError.mapError(error)
        }
    }

    // MARK: - TLS Configuration

    /// Convert abstract DatabaseTLSMode to NIOSSL TLSConfiguration
    private static func makeTLSConfiguration(for mode: DatabaseTLSMode) -> TLSConfiguration? {
        switch mode {
        case .disable:
            return nil
        case .require:
            var config = TLSConfiguration.makeClientConfiguration()
            config.certificateVerification = .none
            return config
        case .verifyCA:
            var config = TLSConfiguration.makeClientConfiguration()
            config.certificateVerification = .noHostnameVerification
            return config
        case .verifyFull:
            return TLSConfiguration.makeClientConfiguration()
        }
    }

    /// Disconnect from database (keeps EventLoopGroup alive for reuse)
    /// Call shutdown() for full cleanup including EventLoopGroup
    func disconnect() async {
        logger.info("Disconnecting from PostgreSQL")

        // Close connection but keep EventLoopGroup for reuse
        // This prevents "Cannot schedule tasks on an EventLoop that has already shut down"
        // errors when rapidly switching connections
        if let conn = connection {
            logger.debug("Closing PostgreSQL connection")
            do {
                try await conn.close()
            } catch {
                logger.error("Error closing connection: \(error)")
            }
            connection = nil
            wrappedConnection = nil
        }

        logger.info("Disconnected from PostgreSQL")
    }

    /// Interrupt in-flight work when superseded by a newer table-browse request.
    /// Preserves stored connection parameters and EventLoopGroup so reconnect remains fast.
    func interruptInFlightOperationForSupersession() async {
        logger.debug("Interrupting in-flight operation for supersession")

        // Invalidate all in-flight work tied to older generations.
        connectionGeneration &+= 1

        // Clear active connection references immediately so stale tasks cannot keep using them.
        let activeConnection = connection
        connection = nil
        wrappedConnection = nil

        // Preserve storedParams + EventLoopGroup for quick reconnect on next operation.
        guard let activeConnection else { return }
        do {
            try await activeConnection.close()
        } catch {
            logger.debug("Connection close during supersession interrupt returned error: \(error)")
        }
    }

    /// Full shutdown including EventLoopGroup - call on app termination
    func shutdown() async {
        logger.info("Shutting down PostgresConnectionManager")

        // Clear stored params on full shutdown
        storedParams = nil

        // Disconnect first
        await disconnect()

        // Now shutdown EventLoopGroup
        if let elg = eventLoopGroup {
            logger.debug("Shutting down EventLoopGroup")

            do {
                try await elg.shutdownGracefully()
                logger.info("✅ EventLoopGroup shutdown completed")
            } catch {
                logger.error("❌ Error shutting down EventLoopGroup: \(error)")
            }

            eventLoopGroup = nil
        }

        logger.info("PostgresConnectionManager shutdown complete")
    }

    // MARK: - Reconnection

    /// Reconnect using stored connection parameters
    private func reconnect() async throws {
        guard let params = storedParams else {
            logger.error("Cannot reconnect: no stored connection parameters")
            throw ConnectionError.notConnected
        }

        logger.info("Attempting to reconnect...")

        // Close the dead connection without clearing params
        if let conn = connection {
            try? await conn.close()
            connection = nil
            wrappedConnection = nil
        }

        // Reconnect using stored params
        try await connect(
            host: params.host,
            port: params.port,
            username: params.username,
            password: params.password,
            database: params.database,
            tlsMode: params.tlsMode
        )
    }

    /// Check if an error indicates a dead/stale connection that should be retried
    ///
    /// Uses PostgresNIO's PSQLError.Code for reliable detection rather than string matching.
    private static func isConnectionError(_ error: Error) -> Bool {
        let logger = Logger.debugLogger(label: "com.postgresgui.connection")

        // Check PSQLError codes (most reliable for PostgresNIO errors)
        if let psqlError = error as? PSQLError {
            let code = psqlError.code
            logger.debug("PSQLError code: \(code)")

            // Connection-related codes that indicate the connection is dead
            if code == .serverClosedConnection ||
               code == .connectionError ||
               code == .uncleanShutdown ||
               code == .messageDecodingFailure {
                logger.debug("Detected connection error: \(code)")
                return true
            }
            // Don't retry on clientClosedConnection (we closed it intentionally)
            // Don't retry on queryCancelled (just the query was cancelled)
            // Don't retry on server errors (SQL errors, auth errors, etc.)
            return false
        }

        // Check for NIO-level connection errors
        if error is NIOConnectionError {
            return true
        }

        // Check our own ConnectionError type
        if let connError = error as? ConnectionError {
            switch connError {
            case .timeout, .networkUnreachable, .notConnected:
                return true
            default:
                return false
            }
        }

        return false
    }

    // MARK: - Connection Access

    /// Execute an operation with the active connection
    /// - Parameter operation: Async closure that receives the abstract DatabaseConnectionProtocol
    /// - Returns: Result of the operation
    /// - Throws: ConnectionError.notConnected if not connected, or operation errors
    ///
    /// If a connection error is detected, this method will attempt to reconnect once and retry the operation.
    func withConnection<T>(_ operation: @escaping (DatabaseConnectionProtocol) async throws -> T) async throws -> T {
        try Task.checkCancellation()

        guard let wrappedConn = wrappedConnection else {
            // No connection - try to reconnect if we have stored params
            if storedParams != nil {
                logger.info("No active connection, attempting reconnect...")
                try Task.checkCancellation()
                try await reconnect()
                try Task.checkCancellation()
                guard let newConn = wrappedConnection else {
                    throw ConnectionError.notConnected
                }
                return try await operation(newConn)
            }
            logger.error("Attempted to use connection while not connected")
            throw ConnectionError.notConnected
        }

        do {
            let result = try await operation(wrappedConn)
            return result
        } catch {
            // Log detailed error info for debugging
            logger.error("Operation error: \(String(reflecting: error))")

            // Check if this is a connection error that we should retry
            let shouldRetry = Self.isConnectionError(error)
            logger.debug("isConnectionError returned: \(shouldRetry), storedParams exists: \(storedParams != nil)")

            if shouldRetry && storedParams != nil {
                logger.warning("Connection error detected, attempting reconnect")
                try Task.checkCancellation()
                do {
                    try await reconnect()
                    try Task.checkCancellation()
                    guard let newConn = wrappedConnection else {
                        throw ConnectionError.notConnected
                    }
                    logger.info("Reconnected successfully, retrying operation...")
                    return try await operation(newConn)
                } catch {
                    if error is CancellationError {
                        throw error
                    }
                    logger.error("Reconnect failed: \(String(reflecting: error))")
                    throw PostgresError.mapError(error)
                }
            }

            if error is CancellationError {
                throw error
            }
            logger.error("Operation failed (non-connection error)")
            throw PostgresError.mapError(error)
        }
    }

    // MARK: - Test Connection

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
        tlsMode: DatabaseTLSMode = .disable
    ) async throws -> Bool {
        let logger = Logger.debugLogger(label: "com.postgresgui.connection.test")
        logger.info("Testing connection to \(host):\(port)")

        // Create temporary EventLoopGroup
        let elg = MultiThreadedEventLoopGroup(numberOfThreads: 1)

        // Build configuration
        var config = PostgresConnection.Configuration(
            host: host,
            port: port,
            username: username,
            password: password,
            database: database,
            tls: .disable
        )

        // Configure TLS based on mode
        if let tlsConfig = makeTLSConfiguration(for: tlsMode) {
            do {
                let sslContext = try NIOSSLContext(configuration: tlsConfig)
                config.tls = .require(sslContext)
                logger.debug("SSL context created successfully for test")
            } catch {
                logger.error("Failed to create SSL context for test: \(error)")
                // Cleanup ELG before throwing
                try? await elg.shutdownGracefully()
                throw ConnectionError.sslContextCreationFailed(error.localizedDescription)
            }
        }

        do {
            // Attempt connection
            let connection = try await PostgresConnection.connect(
                on: elg.next(),
                configuration: config,
                id: 1,
                logger: logger
            )

            // Close immediately
            try await connection.close()
            logger.debug("Test connection closed")

            // Shutdown event loop group
            logger.debug("Shutting down test EventLoopGroup")
            try await elg.shutdownGracefully()
            logger.info("✅ Test EventLoopGroup shutdown completed")

            logger.info("Connection test successful")
            return true
        } catch {
            // Shutdown event loop group on error
            try? await elg.shutdownGracefully()
            logger.error("Connection test failed: \(error)")
            throw PostgresError.mapError(error)
        }
    }
}
