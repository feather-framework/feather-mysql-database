//
//  MySQLDatabaseClient.swift
//  feather-mysql-database
//
//  Created by Tibor Bödecs on 2026. 01. 10..
//

import FeatherDatabase
import Logging
import MySQLNIO

/// A MySQL-backed database client.
///
/// Use this client to execute queries and manage transactions on MySQL.
public struct MySQLDatabaseClient: DatabaseClient {

    public typealias Connection = MySQLDatabaseConnection

    var connection: MySQLDatabaseConnection
    var logger: Logger

    /// Create a MySQL database client.
    ///
    /// Use this initializer to provide an already-open connection.
    /// - Parameters:
    ///   - connection: The MySQL connection to use.
    ///   - logger: The logger for database operations.
    public init(
        connection: MySQLConnection,
        logger: Logger
    ) {
        self.connection = .init(
            connection: connection,
            logger: logger
        )
        self.logger = logger
    }

    // MARK: - database api

    /// Execute work using the stored connection.
    ///
    /// The closure is executed with the current connection.
    /// - Parameter closure: A closure that receives the MySQL connection.
    /// - Throws: A `DatabaseError` if the connection fails.
    /// - Returns: The query result produced by the closure.
    @discardableResult
    public func withConnection<T>(
        _ closure: (Connection) async throws -> T
    ) async throws(DatabaseError) -> T {
        do {
            return try await closure(connection)
        }
        catch let error as DatabaseError {
            throw error
        }
        catch {
            throw .connection(error)
        }
    }

    /// Execute work inside a MySQL transaction.
    ///
    /// The closure runs between `START TRANSACTION` and `COMMIT` with rollback on failure.
    /// - Parameter closure: A closure that receives the MySQL connection.
    /// - Throws: A `DatabaseError` if transaction handling fails.
    /// - Returns: The query result produced by the closure.
    @discardableResult
    public func withTransaction<T>(
        _ closure: (Connection) async throws -> T
    ) async throws(DatabaseError) -> T {

        do {
            try await connection.run(query: "START TRANSACTION;") { _ in }
        }
        catch {
            throw DatabaseError.transaction(
                MySQLTransactionError(
                    beginError: error
                )
            )
        }

        var closureHasFinished = false

        do {
            let result = try await closure(connection)
            closureHasFinished = true

            do {
                try await connection.run(query: "COMMIT;") { _ in }
            }
            catch {
                throw DatabaseError.transaction(
                    MySQLTransactionError(commitError: error)
                )
            }

            return result
        }
        catch {
            var txError = MySQLTransactionError()

            if !closureHasFinished {
                txError.closureError = error

                do {
                    try await connection.run(query: "ROLLBACK;") { _ in }
                }
                catch {
                    txError.rollbackError = error
                }
            }
            else {
                txError.commitError = error
            }

            throw DatabaseError.transaction(txError)
        }
    }

}
