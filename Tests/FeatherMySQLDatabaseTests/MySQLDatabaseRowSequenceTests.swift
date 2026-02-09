//
//  MySQLDatabaseRowSequenceTests.swift
//  feather-mysql-database
//
//  Created by Tibor Bödecs on 2026. 02. 09..
//

import FeatherDatabase
import MySQLNIO
import Testing

@testable import FeatherMySQLDatabase

extension MySQLDatabaseTestSuite {

    @Test
    func rowSequenceIteratesRowsInOrder() async throws {
        try await runUsingTestDatabaseClient { database in
            let suffix = randomTableSuffix()
            let table = "planets_\(suffix)"

            try await database.withConnection { connection in
                try await connection.run(
                    query: #"""
                        DROP TABLE IF EXISTS `\#(unescaped: table)`;
                        """#
                )
                try await connection.run(
                    query: #"""
                        CREATE TABLE IF NOT EXISTS `\#(unescaped: table)` (
                            `id` INTEGER PRIMARY KEY,
                            `name` TEXT
                        );
                        """#
                )

                try await connection.run(
                    query: #"""
                        INSERT INTO `\#(unescaped: table)` (`id`, `name`)
                        VALUES
                            (1, 'Mercury'),
                            (2, 'Venus');
                        """#
                )

                let sequence = try await connection.run(
                    query: #"""
                        SELECT *
                        FROM `\#(unescaped: table)`
                        ORDER BY `id` ASC;
                        """#
                )

                var iterator = sequence.makeAsyncIterator()

                let first = await iterator.next()
                #expect(first != nil)
                #expect(
                    try first?.decode(column: "name", as: String.self)
                        == "Mercury"
                )

                let second = await iterator.next()
                #expect(second != nil)
                #expect(
                    try second?.decode(column: "name", as: String.self)
                        == "Venus"
                )

                let third = await iterator.next()
                #expect(third == nil)
            }
        }
    }

    @Test
    func rowSequenceCollectReturnsAllRows() async throws {
        try await runUsingTestDatabaseClient { database in
            let suffix = randomTableSuffix()
            let table = "greetings_\(suffix)"

            try await database.withConnection { connection in
                try await connection.run(
                    query: #"""
                        DROP TABLE IF EXISTS `\#(unescaped: table)`;
                        """#
                )
                try await connection.run(
                    query: #"""
                        CREATE TABLE IF NOT EXISTS `\#(unescaped: table)` (
                            `id` INTEGER PRIMARY KEY,
                            `name` TEXT
                        );
                        """#
                )

                try await connection.run(
                    query: #"""
                        INSERT INTO `\#(unescaped: table)` (`id`, `name`)
                        VALUES
                            (1, 'Hello'),
                            (2, 'World');
                        """#
                )

                let sequence = try await connection.run(
                    query: #"""
                        SELECT
                            `id`,
                            `name`
                        FROM `\#(unescaped: table)`
                        ORDER BY `id` ASC;
                        """#
                )

                let rows = try await sequence.collect()
                #expect(rows.count == 2)

                let firstName = try rows[0]
                    .decode(
                        column: "name",
                        as: String.self
                    )
                let secondName = try rows[1]
                    .decode(
                        column: "name",
                        as: String.self
                    )

                #expect(firstName == "Hello")
                #expect(secondName == "World")
            }
        }
    }

    @Test
    func rowSequenceHandlesEmptyResults() async throws {
        try await runUsingTestDatabaseClient { database in
            let suffix = randomTableSuffix()
            let table = "empty_rows_\(suffix)"

            try await database.withConnection { connection in
                try await connection.run(
                    query: #"""
                        DROP TABLE IF EXISTS `\#(unescaped: table)`;
                        """#
                )
                try await connection.run(
                    query: #"""
                        CREATE TABLE IF NOT EXISTS `\#(unescaped: table)` (
                            `id` INTEGER PRIMARY KEY,
                            `name` TEXT
                        );
                        """#
                )

                let sequence = try await connection.run(
                    query: #"""
                        SELECT
                            `id`,
                            `name`
                        FROM `\#(unescaped: table)`
                        WHERE
                            1=0;
                        """#
                )

                let rows = try await sequence.collect()
                #expect(rows.isEmpty)

                var iterator = sequence.makeAsyncIterator()
                let first = await iterator.next()
                #expect(first == nil)
            }
        }
    }
}
