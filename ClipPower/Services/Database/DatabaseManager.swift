import Foundation
import GRDB

/// 管理 GRDB 数据库连接与 schema 迁移。
final class DatabaseManager: Sendable {
    static let shared = DatabaseManager()

    let dbQueue: DatabaseQueue

    /// 生产环境单例：数据库文件位于 Application Support 目录。
    private convenience init() {
        let dbQueue = Self.makeProductionDatabaseQueue()
        self.init(dbQueue: dbQueue)
    }

    /// 测试/预览可注入内存数据库或临时文件数据库。
    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
        do {
            try Self.migrator.migrate(dbQueue)
        } catch {
            fatalError("数据库迁移失败: \(error)")
        }
    }

    private static func makeProductionDatabaseQueue() -> DatabaseQueue {
        do {
            let fileManager = FileManager.default
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directory = appSupport.appendingPathComponent("ClipPower", isDirectory: true)
            if !fileManager.fileExists(atPath: directory.path) {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }

            let dbURL = directory.appendingPathComponent("clippower.sqlite")
            let queue = try DatabaseQueue(path: dbURL.path)

            if fileManager.fileExists(atPath: dbURL.path) {
                try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dbURL.path)
            }

            return queue
        } catch {
            fatalError("无法创建数据库文件: \(error)")
        }
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_createSnippetSchema") { db in
            try db.execute(sql: """
                CREATE TABLE snippet (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    keyword TEXT,
                    contentType TEXT NOT NULL DEFAULT 'plainText',
                    plainContent TEXT,
                    cipherContent BLOB,
                    keyID TEXT,
                    visibility TEXT NOT NULL DEFAULT 'normal',
                    tags TEXT,
                    usageCount INTEGER NOT NULL DEFAULT 0,
                    lastUsedAt REAL,
                    createdAt REAL NOT NULL,
                    updatedAt REAL NOT NULL,
                    isDeleted INTEGER NOT NULL DEFAULT 0,
                    deletedAt REAL
                )
                """)

            try db.execute(sql: """
                CREATE UNIQUE INDEX idx_snippet_keyword
                ON snippet(keyword)
                WHERE keyword IS NOT NULL AND isDeleted = 0
                """)

            try db.execute(sql: """
                CREATE VIRTUAL TABLE snippet_fts USING fts5(
                    id UNINDEXED,
                    name,
                    keyword,
                    searchableContent,
                    tags,
                    content='snippet',
                    content_rowid='rowid'
                )
                """)

            // 触发器同步维护 FTS 索引；加密隐藏内容永不写入 searchableContent。
            try db.execute(sql: """
                CREATE TRIGGER snippet_ai AFTER INSERT ON snippet BEGIN
                    INSERT INTO snippet_fts(rowid, id, name, keyword, searchableContent, tags)
                    VALUES (
                        new.rowid, new.id, new.name, new.keyword,
                        CASE WHEN new.visibility = 'encryptedHidden' THEN '' ELSE coalesce(new.plainContent, '') END,
                        coalesce(new.tags, '')
                    );
                END
                """)

            try db.execute(sql: """
                CREATE TRIGGER snippet_ad AFTER DELETE ON snippet BEGIN
                    INSERT INTO snippet_fts(snippet_fts, rowid, id, name, keyword, searchableContent, tags)
                    VALUES (
                        'delete', old.rowid, old.id, old.name, old.keyword,
                        CASE WHEN old.visibility = 'encryptedHidden' THEN '' ELSE coalesce(old.plainContent, '') END,
                        coalesce(old.tags, '')
                    );
                END
                """)

            try db.execute(sql: """
                CREATE TRIGGER snippet_au AFTER UPDATE ON snippet BEGIN
                    INSERT INTO snippet_fts(snippet_fts, rowid, id, name, keyword, searchableContent, tags)
                    VALUES (
                        'delete', old.rowid, old.id, old.name, old.keyword,
                        CASE WHEN old.visibility = 'encryptedHidden' THEN '' ELSE coalesce(old.plainContent, '') END,
                        coalesce(old.tags, '')
                    );
                    INSERT INTO snippet_fts(rowid, id, name, keyword, searchableContent, tags)
                    VALUES (
                        new.rowid, new.id, new.name, new.keyword,
                        CASE WHEN new.visibility = 'encryptedHidden' THEN '' ELSE coalesce(new.plainContent, '') END,
                        coalesce(new.tags, '')
                    );
                END
                """)
        }

        migrator.registerMigration("v2_createClipboardHistory") { db in
            try db.execute(sql: """
                CREATE TABLE clipboardHistoryItem (
                    id TEXT PRIMARY KEY NOT NULL,
                    content TEXT NOT NULL,
                    createdAt REAL NOT NULL
                )
                """)

            try db.execute(sql: """
                CREATE INDEX idx_clipboardHistoryItem_createdAt
                ON clipboardHistoryItem(createdAt DESC)
                """)
        }

        // 剪贴板历史支持图片/文件：把单一 content 字段拆成按类型区分的字段。
        // SQLite 不支持直接改列约束，用"建新表→搬数据→删旧表"的方式迁移。
        migrator.registerMigration("v3_clipboardHistoryRichContent") { db in
            try db.execute(sql: "ALTER TABLE clipboardHistoryItem RENAME TO clipboardHistoryItem_old")

            try db.execute(sql: """
                CREATE TABLE clipboardHistoryItem (
                    id TEXT PRIMARY KEY NOT NULL,
                    kind TEXT NOT NULL DEFAULT 'text',
                    textContent TEXT,
                    imageData BLOB,
                    imageWidth INTEGER,
                    imageHeight INTEGER,
                    fileURLs TEXT,
                    byteSize INTEGER,
                    createdAt REAL NOT NULL
                )
                """)

            // fileURLs 在 Swift 模型里是非空的 [String]（不是 [String]?），旧数据没有
            // 这个字段，必须显式填 '[]' 而不是留 NULL，否则 GRDB 解码这一行就会报错，
            // 而且是整批一起解码——一行解码失败会导致查询整体返回空，看起来就是
            // "剪贴板历史全没了"。
            try db.execute(sql: """
                INSERT INTO clipboardHistoryItem (id, kind, textContent, fileURLs, createdAt)
                SELECT id, 'text', content, '[]', createdAt FROM clipboardHistoryItem_old
                """)

            try db.execute(sql: "DROP TABLE clipboardHistoryItem_old")

            try db.execute(sql: """
                CREATE INDEX idx_clipboardHistoryItem_createdAt
                ON clipboardHistoryItem(createdAt DESC)
                """)
        }

        // 补丁迁移：修复上面 v3 迁移的疏漏——已经跑过 v3 的机器上，fileURLs 是 NULL，
        // 解码会报错导致查询整体失败。这里直接补成 '[]'。
        migrator.registerMigration("v4_backfillClipboardFileURLs") { db in
            try db.execute(sql: "UPDATE clipboardHistoryItem SET fileURLs = '[]' WHERE fileURLs IS NULL")
        }

        return migrator
    }
}
