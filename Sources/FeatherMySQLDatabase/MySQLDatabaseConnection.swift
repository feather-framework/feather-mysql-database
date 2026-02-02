//
//  MySQLConnection.swift
//  feather-mysql-database
//
//  Created by Tibor Bödecs on 2026. 01. 10..
//

import FeatherDatabase
import MySQLNIO
import NIOCore

public struct MySQLDatabaseConnection: DatabaseConnection, Sendable {

    public typealias Query = MySQLQuery
    public typealias RowSequence = MySQLRowSequence

    let connection: MySQLNIO.MySQLConnection
    public var logger: Logging.Logger

    /// Execute a MySQL query on this connection.
    ///
    /// This wraps `MySQLNIO` query execution and maps errors.
    /// - Parameters:
    ///  - query: The MySQL query to execute.
    ///  - handler: A closure that transforms the result into a generic value.
    /// - Throws: A `DatabaseError` if the query fails.
    /// - Returns: A query result containing the returned rows.
    @discardableResult
    public func run<T: Sendable>(
        query: Query,
        _ handler: (RowSequence) async throws -> T = { _ in }
    ) async throws(DatabaseError) -> T {
        do {
            let rows =
                try await connection.query(
                    query.sql,
                    query.bindings
                )
                .get()

            return try await handler(
                MySQLRowSequence(
                    elements: rows.map {
                        .init(
                            row: $0
                        )
                    }
                )
            )
        }
        catch {
            throw .query(error)
        }
    }
}
