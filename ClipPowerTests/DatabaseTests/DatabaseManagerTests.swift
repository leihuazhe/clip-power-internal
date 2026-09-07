import XCTest
import GRDB
@testable import ClipPower

final class DatabaseManagerTests: XCTestCase {
    func testMigrationCreatesSnippetTable() throws {
        let dbQueue = try DatabaseQueue()
        let manager = DatabaseManager(dbQueue: dbQueue)

        let exists = try manager.dbQueue.read { db in
            try db.tableExists("snippet")
        }
        XCTAssertTrue(exists)
    }

    func testMigrationCreatesFTSTable() throws {
        let dbQueue = try DatabaseQueue()
        let manager = DatabaseManager(dbQueue: dbQueue)

        let exists = try manager.dbQueue.read { db in
            try db.tableExists("snippet_fts")
        }
        XCTAssertTrue(exists)
    }

    func testKeywordUniqueIndexRejectsDuplicateActiveKeywords() throws {
        let dbQueue = try DatabaseQueue()
        let manager = DatabaseManager(dbQueue: dbQueue)

        try manager.dbQueue.write { db in
            try db.execute(sql: Self.insertSQL, arguments: ["id-1", "First", "dup", "normal", 0])
        }

        XCTAssertThrowsError(
            try manager.dbQueue.write { db in
                try db.execute(sql: Self.insertSQL, arguments: ["id-2", "Second", "dup", "normal", 0])
            }
        )
    }

    func testKeywordUniqueIndexIgnoresSoftDeletedRows() throws {
        let dbQueue = try DatabaseQueue()
        let manager = DatabaseManager(dbQueue: dbQueue)

        try manager.dbQueue.write { db in
            try db.execute(sql: Self.insertSQL, arguments: ["id-1", "First", "dup", "normal", 1])
            try db.execute(sql: Self.insertSQL, arguments: ["id-2", "Second", "dup", "normal", 0])
        }

        let activeCount = try manager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM snippet WHERE keyword = ?", arguments: ["dup"])
        }
        XCTAssertEqual(activeCount, 2)
    }

    func testEncryptedHiddenContentIsNotIndexedInFTS() throws {
        let dbQueue = try DatabaseQueue()
        let manager = DatabaseManager(dbQueue: dbQueue)

        try manager.dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO snippet (id, name, keyword, contentType, plainContent, visibility, isDeleted, createdAt, updatedAt)
                VALUES (?, ?, ?, 'plainText', ?, 'encryptedHidden', 0, 0, 0)
                """,
                arguments: ["id-3", "密钥", "secretkey", "supersecretplaintext"]
            )
        }

        let hits = try manager.dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM snippet_fts WHERE searchableContent MATCH ?",
                arguments: ["supersecretplaintext"]
            )
        }
        XCTAssertEqual(hits, 0)
    }

    private static let insertSQL = """
        INSERT INTO snippet (id, name, keyword, visibility, isDeleted, createdAt, updatedAt)
        VALUES (?, ?, ?, ?, ?, 0, 0)
        """
}
