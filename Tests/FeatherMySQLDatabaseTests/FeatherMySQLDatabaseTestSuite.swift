//
//  FeatherMySQLDatabaseTestSuite.swift
//  feather-mysql-database
//
//  Created by Tibor Bödecs on 2026. 01. 10..
//

import FeatherDatabase
import Logging
import MySQLNIO
import NIOCore
import NIOPosix
import NIOSSL
import Testing

@testable import FeatherMySQLDatabase

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Suite
struct MySQLDatabaseTestSuite {

    private func randomTableSuffix() -> String {
        let characters = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        var suffix = ""
        suffix.reserveCapacity(16)
        for _ in 0..<16 {
            suffix.append(characters.randomElement() ?? "a")
        }
        return suffix
    }

    private func runUsingTestDatabaseClient(
        _ closure: ((MySQLDatabaseClient) async throws -> Void)
    ) async throws {
        var logger = Logger(label: "test")
        logger.logLevel = .info

        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)

        let finalCertPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docker")
            .appendingPathComponent("mariadb")
            .appendingPathComponent("certificates")
            .appendingPathComponent("ca.pem")
            .path()

        var tlsConfig = TLSConfiguration.makeClientConfiguration()
        let rootCert = try NIOSSLCertificate.fromPEMFile(finalCertPath)
        tlsConfig.trustRoots = .certificates(rootCert)
        tlsConfig.certificateVerification = .fullVerification

        let connection =
            try await MySQLConnection.connect(
                to: try SocketAddress(ipAddress: "127.0.0.1", port: 3306),
                username: "mariadb",
                database: "mariadb",
                password: "mariadb",
                tlsConfiguration: tlsConfig,
                logger: logger,
                on: eventLoopGroup.next()
            )
            .get()

        let database = MySQLDatabaseClient(
            connection: connection,
            logger: logger
        )

        do {
            try await closure(database)

            try await connection.close().get()
            try await eventLoopGroup.shutdownGracefully()
        }
        catch {
            try await connection.close().get()
            try await eventLoopGroup.shutdownGracefully()

            Issue.record(error)
        }
    }

    // MARK: -

    @Test
    func foreignKeySupport() async throws {
        try await runUsingTestDatabaseClient { database in
            let suffix = randomTableSuffix()
            let planetsTable = "planets_\(suffix)"
            let moonsTable = "moons_\(suffix)"

            try await database.withConnection { connection in

                try await connection.run(
                    query: #"""
                        DROP TABLE IF EXISTS `\#(unescaped: moonsTable)`;
                        """#
                )
                try await connection.run(
                    query: #"""
                        DROP TABLE IF EXISTS `\#(unescaped: planetsTable)`;
                        """#
                )

                try await connection.run(
                    query: #"""
                        CREATE TABLE `\#(unescaped: planetsTable)` (
                            `id` INTEGER PRIMARY KEY,
                            `name` TEXT NOT NULL
                        ) ENGINE=InnoDB;
                        """#
                )
                try await connection.run(
                    query: #"""
                        CREATE TABLE `\#(unescaped: moonsTable)` (
                            `id` INTEGER PRIMARY KEY,
                            `planet_id` INTEGER NOT NULL,
                            CONSTRAINT `fk_\#(unescaped: moonsTable)`
                                FOREIGN KEY (`planet_id`)
                                REFERENCES `\#(unescaped: planetsTable)` (`id`)
                        ) ENGINE=InnoDB;
                        """#
                )

                do {
                    _ = try await connection.run(
                        query: #"""
                            INSERT INTO `\#(unescaped: moonsTable)`
                                (`id`, `planet_id`)
                            VALUES
                                (1, 999);
                            """#
                    )
                    Issue.record("Expected foreign key constraint violation.")
                }
                catch DatabaseError.query(let error) {
                    #expect(
                        "\(error)".contains("foreign key constraint fails")
                    )
                }
                catch {
                    Issue.record("Expected database query error to be thrown.")
                }
            }
        }
    }

    @Test
    func tableCreation() async throws {
        try await runUsingTestDatabaseClient { database in
            let suffix = randomTableSuffix()
            let table = "galaxies_\(suffix)"

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

                let results = try await connection.run(
                    query: #"""
                        SELECT `table_name`
                        FROM `information_schema`.`tables`
                        WHERE `table_schema` = DATABASE()
                            AND `table_name` = '\#(unescaped: table)'
                        ORDER BY `table_name`;
                        """#
                ) { try await $0.collect() }

                #expect(results.count == 1)

                let item = results[0]
                let name = try item.decode(
                    column: "table_name",
                    as: String.self
                )
                #expect(name == table)
            }
        }
    }

    @Test
    func tableInsert() async throws {
        try await runUsingTestDatabaseClient { database in
            let suffix = randomTableSuffix()
            let table = "galaxies_\(suffix)"

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

                let name1 = "Andromeda"
                let name2 = "Milky Way"

                try await connection.run(
                    query: #"""
                        INSERT INTO `\#(unescaped: table)`
                            (`id`, `name`)
                        VALUES
                            (\#(1), \#(name1)),
                            (\#(2), \#(name2));
                        """#
                )

                let results = try await connection.run(
                    query: #"""
                        SELECT * FROM `\#(unescaped: table)` ORDER BY `name` ASC;
                        """#
                ) { try await $0.collect() }

                #expect(results.count == 2)

                let item1 = results[0]
                let name1result = try item1.decode(
                    column: "name",
                    as: String.self
                )
                #expect(name1result == name1)

                let item2 = results[1]
                let name2result = try item2.decode(
                    column: "name",
                    as: String.self
                )
                #expect(name2result == name2)
            }
        }
    }

    @Test
    func rowDecoding() async throws {
        try await runUsingTestDatabaseClient { database in
            let suffix = randomTableSuffix()
            let table = "foo_\(suffix)"

            try await database.withConnection { connection in

                try await connection.run(
                    query: #"""
                        DROP TABLE IF EXISTS `\#(unescaped: table)`;
                        """#
                )
                try await connection.run(
                    query: #"""
                        CREATE TABLE `\#(unescaped: table)` (
                            `id` INTEGER NOT NULL PRIMARY KEY,
                            `value` TEXT
                        );
                        """#
                )

                try await connection.run(
                    query: #"""
                        INSERT INTO `\#(unescaped: table)`
                            (`id`, `value`)
                        VALUES
                            (1, 'abc'),
                            (2, NULL);
                        """#
                )

                let result =
                    try await connection.run(
                        query: #"""
                            SELECT `id`, `value`
                            FROM `\#(unescaped: table)`
                            ORDER BY `id`;
                            """#
                    ) { try await $0.collect() }

                #expect(result.count == 2)

                let item1 = result[0]
                let item2 = result[1]

                #expect(try item1.decode(column: "id", as: Int.self) == 1)
                #expect(try item2.decode(column: "id", as: Int.self) == 2)

                #expect(
                    try item1.decode(column: "id", as: Int?.self) == .some(1)
                )
                #expect(
                    (try? item1.decode(column: "value", as: Int?.self)) == nil
                )

                #expect(
                    try item1.decode(column: "value", as: String.self) == "abc"
                )
                #expect(
                    (try? item2.decode(column: "value", as: String.self)) == nil
                )

                #expect(
                    (try item1.decode(column: "value", as: String?.self))
                        == .some("abc")
                )
                #expect(
                    (try item2.decode(column: "value", as: String?.self))
                        == .none
                )
            }
        }
    }

    @Test
    func queryEncoding() async throws {
        try await runUsingTestDatabaseClient { database in
            let suffix = randomTableSuffix()
            let table = "foo_\(suffix)"

            try await database.withConnection { connection in

                try await connection.run(
                    query: #"""
                        DROP TABLE IF EXISTS `\#(unescaped: table)`;
                        """#
                )

                let row1: (Int, String?) = (1, "abc")
                let row2: (Int, String?) = (2, nil)

                try await connection.run(
                    query: #"""
                        CREATE TABLE `\#(unescaped: table)` (
                            `id` INTEGER NOT NULL PRIMARY KEY,
                            `value` TEXT
                        );
                        """#
                )

                try await connection.run(
                    query: #"""
                        INSERT INTO `\#(unescaped: table)`
                            (`id`, `value`)
                        VALUES
                            (\#(row1.0), \#(row1.1)),
                            (\#(row2.0), \#(row2.1));
                        """#
                )

                let result =
                    try await connection.run(
                        query: #"""
                            SELECT `id`, `value`
                            FROM `\#(unescaped: table)`
                            ORDER BY `id` ASC;
                            """#
                    ) { try await $0.collect() }

                #expect(result.count == 2)

                let item1 = result[0]
                let item2 = result[1]

                #expect(try item1.decode(column: "id", as: Int.self) == 1)
                #expect(try item2.decode(column: "id", as: Int.self) == 2)

                #expect(
                    try item1.decode(column: "value", as: String?.self) == "abc"
                )
                #expect(
                    try item2.decode(column: "value", as: String?.self) == nil
                )
            }
        }
    }

    @Test
    func unsafeSQLBindings() async throws {
        try await runUsingTestDatabaseClient { database in
            let suffix = randomTableSuffix()
            let table = "widgets_\(suffix)"

            try await database.withConnection { connection in

                try await connection.run(
                    query: #"""
                        DROP TABLE IF EXISTS `\#(unescaped: table)`;
                        """#
                )
                try await connection.run(
                    query: #"""
                        CREATE TABLE `\#(unescaped: table)` (
                            `id` INTEGER NOT NULL PRIMARY KEY,
                            `name` TEXT NOT NULL
                        );
                        """#
                )

                let insert = MySQLQuery(
                    unsafeSQL: #"""
                        INSERT INTO `\#(table)`
                            (`id`, `name`)
                        VALUES
                            (?, ?);
                        """#,
                    bindings: [.init(int: 1), .init(string: "gizmo")]
                )

                try await connection.run(query: insert)

                let result =
                    try await connection.run(
                        query: #"""
                            SELECT `name`
                            FROM `\#(unescaped: table)`
                            WHERE `id` = 1;
                            """#
                    ) { try await $0.collect() }

                #expect(result.count == 1)
                #expect(
                    try result[0].decode(column: "name", as: String.self)
                        == "gizmo"
                )
            }
        }
    }

    @Test
    func optionalStringInterpolationNil() async throws {
        try await runUsingTestDatabaseClient { database in
            let suffix = randomTableSuffix()
            let table = "notes_\(suffix)"

            try await database.withConnection { connection in

                try await connection.run(
                    query: #"""
                        DROP TABLE IF EXISTS `\#(unescaped: table)`;
                        """#
                )
                try await connection.run(
                    query: #"""
                        CREATE TABLE `\#(unescaped: table)` (
                            `id` INTEGER NOT NULL PRIMARY KEY,
                            `body` TEXT
                        );
                        """#
                )

                let body: String? = nil
                let insert: MySQLQuery = #"""
                    INSERT INTO `\#(unescaped: table)`
                        (`id`, `body`)
                    VALUES
                        (1, \#(body));
                    """#

                try await connection.run(query: insert)

                let result =
                    try await connection.run(
                        query: #"""
                            SELECT `body`
                            FROM `\#(unescaped: table)`
                            WHERE `id` = 1;
                            """#
                    ) { try await $0.collect() }

                #expect(result.count == 1)
                #expect(
                    try result[0].decode(column: "body", as: String?.self)
                        == nil
                )
            }
        }
    }

    @Test
    func mysqlDataInterpolation() async throws {
        try await runUsingTestDatabaseClient { database in
            let suffix = randomTableSuffix()
            let table = "tags_\(suffix)"

            try await database.withConnection { connection in

                try await connection.run(
                    query: #"""
                        DROP TABLE IF EXISTS `\#(unescaped: table)`;
                        """#
                )
                try await connection.run(
                    query: #"""
                        CREATE TABLE `\#(unescaped: table)` (
                            `id` INTEGER NOT NULL PRIMARY KEY,
                            `label` TEXT NOT NULL
                        );
                        """#
                )

                let label: MySQLData = .init(string: "alpha")
                let insert: MySQLQuery = #"""
                    INSERT INTO `\#(unescaped: table)`
                        (`id`, `label`)
                    VALUES
                        (1, \#(label));
                    """#

                try await connection.run(query: insert)

                let result =
                    try await connection.run(
                        query: #"""
                            SELECT `label`
                            FROM `\#(unescaped: table)`
                            WHERE `id` = 1;
                            """#
                    ) { try await $0.collect() }

                #expect(result.count == 1)
                #expect(
                    try result[0].decode(column: "label", as: String.self)
                        == "alpha"
                )
            }
        }
    }

    @Test
    func resultSequenceIterator() async throws {
        try await runUsingTestDatabaseClient { database in
            let suffix = randomTableSuffix()
            let table = "numbers_\(suffix)"

            try await database.withConnection { connection in
                try await connection.run(
                    query: #"""
                        DROP TABLE IF EXISTS `\#(unescaped: table)`;
                        """#
                )
                try await connection.run(
                    query: #"""
                        CREATE TABLE `\#(unescaped: table)` (
                            `id` INTEGER NOT NULL PRIMARY KEY,
                            `value` TEXT NOT NULL
                        );
                        """#
                )

                try await connection.run(
                    query: #"""
                        INSERT INTO `\#(unescaped: table)`
                            (`id`, `value`)
                        VALUES
                            (1, 'one'),
                            (2, 'two');
                        """#
                )

                let result = try await connection.run(
                    query: #"""
                        SELECT `id`, `value`
                        FROM `\#(unescaped: table)`
                        ORDER BY `id`;
                        """#
                ) { try await $0.collect() }

                #expect(result.count == 2)

                let first = result[0]
                let second = result[1]

                #expect(try first.decode(column: "id", as: Int.self) == 1)
                #expect(
                    try first.decode(column: "value", as: String.self) == "one"
                )

                #expect(try second.decode(column: "id", as: Int.self) == 2)
                #expect(
                    try second.decode(column: "value", as: String.self) == "two"
                )
            }
        }
    }

    @Test
    func collectFirstReturnsFirstRow() async throws {
        try await runUsingTestDatabaseClient { database in
            let suffix = randomTableSuffix()
            let table = "widgets_\(suffix)"

            try await database.withConnection { connection in

                try await connection.run(
                    query: #"""
                        DROP TABLE IF EXISTS `\#(unescaped: table)`;
                        """#
                )
                try await connection.run(
                    query: #"""
                        CREATE TABLE `\#(unescaped: table)` (
                            `id` INTEGER NOT NULL PRIMARY KEY AUTO_INCREMENT,
                            `name` TEXT NOT NULL
                        );
                        """#
                )

                try await connection.run(
                    query: #"""
                        INSERT INTO `\#(unescaped: table)`
                            (`name`)
                        VALUES
                            ('alpha'),
                            ('beta');
                        """#
                )

                let result =
                    try await connection.run(
                        query: #"""
                            SELECT `name`
                            FROM `\#(unescaped: table)`
                            ORDER BY `id` ASC;
                            """#
                    ) { try await $0.collect() }
                    .first

                #expect(
                    try result?.decode(column: "name", as: String.self)
                        == "alpha"
                )
            }
        }
    }

    @Test
    func transactionSuccess() async throws {
        try await runUsingTestDatabaseClient { database in
            let suffix = randomTableSuffix()
            let table = "items_\(suffix)"

            try await database.withConnection { connection in

                try await connection.run(
                    query: #"""
                        DROP TABLE IF EXISTS `\#(unescaped: table)`;
                        """#
                )
                try await connection.run(
                    query: #"""
                        CREATE TABLE `\#(unescaped: table)` (
                            `id` INTEGER NOT NULL PRIMARY KEY,
                            `name` TEXT NOT NULL
                        );
                        """#
                )

                try await database.withTransaction { connection in
                    try await connection.run(
                        query: #"""
                            INSERT INTO `\#(unescaped: table)`
                                (`id`, `name`)
                            VALUES
                                (1, 'widget');
                            """#
                    )
                }

                let result =
                    try await connection.run(
                        query: #"""
                            SELECT `name`
                            FROM `\#(unescaped: table)`
                            WHERE `id` = 1;
                            """#
                    ) { try await $0.collect() }

                #expect(result.count == 1)
                #expect(
                    try result[0].decode(column: "name", as: String.self)
                        == "widget"
                )
            }
        }
    }

    @Test
    func transactionFailurePropagates() async throws {
        try await runUsingTestDatabaseClient { database in
            let suffix = randomTableSuffix()
            let table = "dummy_\(suffix)"

            try await database.withConnection { connection in

                try await connection.run(
                    query: #"""
                        DROP TABLE IF EXISTS `\#(unescaped: table)`;
                        """#
                )
                try await connection.run(
                    query: #"""
                        CREATE TABLE `\#(unescaped: table)` (
                            `id` INTEGER NOT NULL PRIMARY KEY,
                            `name` TEXT NOT NULL
                        );
                        """#
                )
            }

            do {
                try await database.withTransaction { connection in
                    try await connection.run(
                        query: #"""
                            INSERT INTO `\#(unescaped: table)`
                                (`id`, `name`)
                            VALUES
                                (1, 'ok');
                            """#
                    )

                    return try await connection.run(
                        query: #"""
                            INSERT INTO `\#(unescaped: table)`
                                (`id`, `name`)
                            VALUES
                                (2, NULL);
                            """#
                    )
                }
                Issue.record(
                    "Expected database transaction error to be thrown."
                )
            }
            catch DatabaseError.transaction(let error) {
                #expect(error.beginError == nil)
                #expect(error.closureError != nil)
                #expect(
                    error.closureError.debugDescription.contains(
                        "cannot be null"
                    )
                )
                #expect(error.rollbackError == nil)
                #expect(error.commitError == nil)
            }
            catch {
                Issue.record(
                    "Expected database transaction error to be thrown."
                )
            }

            try await database.withConnection { connection in
                let result =
                    try await connection.run(
                        query: #"""
                            SELECT `id`
                            FROM `\#(unescaped: table)`;
                            """#
                    ) { try await $0.collect() }

                #expect(result.isEmpty)
            }
        }
    }

    @Test
    func doubleRoundTrip() async throws {
        try await runUsingTestDatabaseClient { database in
            let suffix = randomTableSuffix()
            let table = "measurements_\(suffix)"

            try await database.withConnection { connection in

                try await connection.run(
                    query: #"""
                        DROP TABLE IF EXISTS `\#(unescaped: table)`;
                        """#
                )
                try await connection.run(
                    query: #"""
                        CREATE TABLE `\#(unescaped: table)` (
                            `id` INTEGER NOT NULL PRIMARY KEY,
                            `value` DOUBLE NOT NULL
                        );
                        """#
                )

                let expected = 1.5

                try await connection.run(
                    query: #"""
                        INSERT INTO `\#(unescaped: table)`
                            (`id`, `value`)
                        VALUES
                            (1, \#(expected));
                        """#
                )

                let result =
                    try await connection.run(
                        query: #"""
                            SELECT `value`
                            FROM `\#(unescaped: table)`
                            WHERE `id` = 1;
                            """#
                    ) { try await $0.collect() }

                #expect(result.count == 1)
                #expect(
                    try result[0].decode(column: "value", as: Double.self)
                        == expected
                )
            }
        }
    }

    @Test
    func missingColumnThrows() async throws {
        try await runUsingTestDatabaseClient { database in
            let suffix = randomTableSuffix()
            let table = "items_\(suffix)"

            try await database.withConnection { connection in

                try await connection.run(
                    query: #"""
                        DROP TABLE IF EXISTS `\#(unescaped: table)`;
                        """#
                )
                try await connection.run(
                    query: #"""
                        CREATE TABLE `\#(unescaped: table)` (
                            `id` INTEGER NOT NULL PRIMARY KEY,
                            `value` TEXT
                        );
                        """#
                )

                try await connection.run(
                    query: #"""
                        INSERT INTO `\#(unescaped: table)`
                            (`id`, `value`)
                        VALUES
                            (1, 'abc');
                        """#
                )

                let result =
                    try await connection.run(
                        query: #"""
                            SELECT `id`
                            FROM `\#(unescaped: table)`;
                            """#
                    ) { try await $0.collect() }

                #expect(result.count == 1)

                do {
                    _ = try result[0].decode(column: "value", as: String.self)
                    Issue.record("Expected decoding a missing column to throw.")
                }
                catch DecodingError.dataCorrupted {

                }
                catch {
                    Issue.record(
                        "Expected a dataCorrupted error for missing column."
                    )
                }
            }
        }
    }

    @Test
    func typeMismatchThrows() async throws {
        try await runUsingTestDatabaseClient { database in
            let suffix = randomTableSuffix()
            let table = "items_\(suffix)"

            try await database.withConnection { connection in

                try await connection.run(
                    query: #"""
                        DROP TABLE IF EXISTS `\#(unescaped: table)`;
                        """#
                )
                try await connection.run(
                    query: #"""
                        CREATE TABLE `\#(unescaped: table)` (
                            `id` INTEGER NOT NULL PRIMARY KEY,
                            `value` TEXT
                        );
                        """#
                )

                try await connection.run(
                    query: #"""
                        INSERT INTO `\#(unescaped: table)`
                            (`id`, `value`)
                        VALUES
                            (1, 'abc');
                        """#
                )

                let result =
                    try await connection.run(
                        query: #"""
                            SELECT `value`
                            FROM `\#(unescaped: table)`;
                            """#
                    ) { try await $0.collect() }

                #expect(result.count == 1)

                do {
                    _ = try result[0].decode(column: "value", as: Int.self)
                    Issue.record("Expected decoding a string as Int to throw.")
                }
                catch DecodingError.typeMismatch {

                }
                catch {
                    Issue.record(
                        "Expected a typeMismatch error when decoding a string as Int."
                    )
                }
            }
        }
    }

    @Test
    func queryFailureErrorText() async throws {
        try await runUsingTestDatabaseClient { database in
            let suffix = randomTableSuffix()
            let table = "missing_table_\(suffix)"

            try await database.withConnection { connection in
                do {
                    _ = try await connection.run(
                        query: #"""
                            SELECT *
                            FROM `\#(unescaped: table)`;
                            """#
                    )
                    Issue.record("Expected query to fail for missing table.")
                }
                catch DatabaseError.query(let error) {
                    #expect("\(error)".contains("doesn't exist"))
                }
                catch {
                    Issue.record("Expected database query error to be thrown.")
                }
            }
        }
    }

    @Test
    func versionCheck() async throws {
        try await runUsingTestDatabaseClient { database in
            try await database.withConnection { connection in
                let result = try await connection.run(
                    query: #"""
                        SELECT
                            VERSION() AS `version`
                        WHERE
                            1=\#(1);
                        """#
                ) { try await $0.collect() }

                #expect(result.count == 1)

                let item = result[0]
                let version = try item.decode(
                    column: "version",
                    as: String.self
                )
                #expect(!version.isEmpty)
            }
        }
    }

    @Test
    func sslCheckStatus() async throws {
        try await runUsingTestDatabaseClient { database in
            try await database.withConnection { connection in
                let result = try await connection.run(
                    query: #"""
                        SHOW VARIABLES LIKE 'have_ssl';
                        """#
                ) { try await $0.collect() }

                #expect(result.count == 1)

                let item = result[0]
                let name = try item.decode(
                    column: "Variable_name",
                    as: String.self
                )
                #expect(name == "have_ssl")

                let value = try item.decode(column: "Value", as: String.self)
                #expect(value == "YES")
            }
        }
    }

    @Test
    func sslCheckCypher() async throws {
        try await runUsingTestDatabaseClient { database in
            try await database.withConnection { connection in
                let result = try await connection.run(
                    query: #"""
                        SHOW SESSION STATUS LIKE "ssl_cipher";
                        """#
                ) { try await $0.collect() }

                #expect(result.count == 1)

                let item = result[0]
                let name = try item.decode(
                    column: "Variable_name",
                    as: String.self
                )
                #expect(name == "Ssl_cipher")

                let value = try item.decode(column: "Value", as: String.self)
                #expect(value == "TLS_AES_128_GCM_SHA256")
            }
        }
    }

    @Test
    func concurrentTransactionUpdates() async throws {
        try await runUsingTestDatabaseClient { database in
            let suffix = randomTableSuffix()
            let table = "sessions_\(suffix)"
            let sessionID = "session_\(suffix)"

            enum TestError: Error {
                case missingRow
            }

            try await database.withConnection { connection in

                try await connection.run(
                    query: #"""
                        DROP TABLE IF EXISTS `\#(unescaped: table)`;
                        """#
                )
                try await connection.run(
                    query: #"""
                        CREATE TABLE `\#(unescaped: table)` (
                            `id` VARCHAR(255) NOT NULL PRIMARY KEY,
                            `access_token` TEXT NOT NULL,
                            `access_expires_at` TIMESTAMP NOT NULL,
                            `refresh_token` TEXT NOT NULL,
                            `refresh_count` INTEGER NOT NULL DEFAULT 0
                        );
                        """#
                )

                // set an expired token
                try await connection.run(
                    query: #"""
                        INSERT INTO `\#(unescaped: table)`
                            (`id`, `access_token`, `access_expires_at`, `refresh_token`, `refresh_count`)
                        VALUES
                            (
                                \#(sessionID),
                                'stale',
                                NOW() - INTERVAL 5 MINUTE,
                                'refresh',
                                0
                            );
                        """#
                )
            }

            func getValidAccessToken(sessionID: String) async throws -> String {
                try await database.withTransaction { connection in
                    let result = try await connection.run(
                        query: #"""
                            SELECT
                                `access_token`,
                                `refresh_count`,
                                `access_expires_at` > NOW() + INTERVAL 60 SECOND AS `is_valid`
                            FROM `\#(unescaped: table)`
                            WHERE `id` = \#(sessionID)
                            FOR UPDATE;
                            """#
                    ) { try await $0.collect() }

                    guard let row = result.first else {
                        throw TestError.missingRow
                    }

                    let isValid = try row.decode(
                        column: "is_valid",
                        as: Bool.self
                    )
                    if isValid {
                        // token was valid, must be called X times
                        return try row.decode(
                            column: "access_token",
                            as: String.self
                        )
                    }

                    // refresh, this branch can only be called 1 time
                    let refreshCount = try row.decode(
                        column: "refresh_count",
                        as: Int.self
                    )
                    let newRefreshCount = refreshCount + 1
                    let newToken = "token_\(newRefreshCount)"

                    try await Task.sleep(for: .milliseconds(40))

                    try await connection.run(
                        query: #"""
                            UPDATE `\#(unescaped: table)`
                            SET
                                `access_token` = \#(newToken),
                                `access_expires_at` = NOW() + INTERVAL 10 MINUTE,
                                `refresh_count` = \#(newRefreshCount)
                            WHERE `id` = \#(sessionID);
                            """#
                    )

                    return newToken
                }
            }

            let workerCount = 80
            var tokens: [String] = []
            try await withThrowingTaskGroup(of: String.self) { group in
                for _ in 0..<workerCount {
                    group.addTask {
                        try await getValidAccessToken(sessionID: sessionID)
                    }
                }
                for try await token in group {
                    tokens.append(token)
                }
            }

            #expect(Set(tokens).count == 1)

            try await database.withConnection { connection in

                let result =
                    try await connection.run(
                        query: #"""
                            SELECT
                                `access_token`,
                                `refresh_count`,
                                `access_expires_at` > NOW() AS `is_valid`
                            FROM `\#(unescaped: table)`
                            WHERE `id` = \#(sessionID);
                            """#
                    ) { try await $0.collect() }

                #expect(result.count == 1)
                #expect(
                    try result[0].decode(column: "refresh_count", as: Int.self)
                        == 1
                )
                #expect(
                    try result[0]
                        .decode(column: "access_token", as: String.self)
                        == "token_1"
                )
                #expect(
                    try result[0].decode(column: "is_valid", as: Bool.self)
                        == true
                )
            }
        }
    }

}
