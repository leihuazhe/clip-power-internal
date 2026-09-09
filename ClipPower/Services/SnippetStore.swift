import Foundation
import GRDB

enum SnippetStoreError: Error, Equatable {
    case duplicateKeyword
    case notFound
}

extension Notification.Name {
    /// 片段被创建/编辑/删除/恢复时发出，`KeywordIndex` 借此知道该刷新关键词缓存了。
    static let snippetsDidChange = Notification.Name("ClipPower.snippetsDidChange")
}

/// CRUD / 搜索 / 回收站的数据层 facade，UI 层只通过它访问数据库。
final class SnippetStore: Sendable {
    let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    @discardableResult
    func create(_ input: Snippet) throws -> Snippet {
        var snippet = input
        let now = Date()
        snippet.createdAt = now
        snippet.updatedAt = now
        do {
            try dbQueue.write { db in
                try snippet.insert(db)
            }
        } catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT {
            throw SnippetStoreError.duplicateKeyword
        }
        postSnippetsDidChange()
        return snippet
    }

    @discardableResult
    func update(_ input: Snippet) throws -> Snippet {
        var snippet = input
        snippet.updatedAt = Date()
        do {
            try dbQueue.write { db in
                try snippet.update(db)
            }
        } catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT {
            throw SnippetStoreError.duplicateKeyword
        }
        postSnippetsDidChange()
        return snippet
    }

    func softDelete(id: String) throws {
        try dbQueue.write { db in
            guard var snippet = try Snippet.fetchOne(db, key: id) else {
                throw SnippetStoreError.notFound
            }
            let now = Date()
            snippet.isDeleted = true
            snippet.deletedAt = now
            snippet.updatedAt = now
            try snippet.update(db)
        }
        postSnippetsDidChange()
    }

    func restore(id: String) throws {
        try dbQueue.write { db in
            guard var snippet = try Snippet.fetchOne(db, key: id) else {
                throw SnippetStoreError.notFound
            }
            snippet.isDeleted = false
            snippet.deletedAt = nil
            snippet.updatedAt = Date()
            try snippet.update(db)
        }
        postSnippetsDidChange()
    }

    func permanentlyDelete(id: String) throws {
        try dbQueue.write { db in
            _ = try Snippet.deleteOne(db, key: id)
        }
        postSnippetsDidChange()
    }

    private func postSnippetsDidChange() {
        NotificationCenter.default.post(name: .snippetsDidChange, object: nil)
    }

    /// 清理超过保留期的回收站条目，App 启动时调用一次。
    @discardableResult
    func purgeExpiredTrash(retentionDays: Int = 30) throws -> Int {
        let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86400)
        return try dbQueue.write { db in
            try Snippet
                .filter(Column("isDeleted") == true)
                .filter(Column("deletedAt") < cutoff)
                .deleteAll(db)
        }
    }

    /// 主列表：所有未删除的条目，不管可见性——软隐藏/加密隐藏的条目也在这里，
    /// UI 层负责按 visibility 打码显示、加锁图标等，而不是从数据层整个排除掉。
    func fetchActive() throws -> [Snippet] {
        try dbQueue.read { db in
            try Snippet
                .filter(Column("isDeleted") == false)
                .order(Column("updatedAt").desc, Column("rowid").desc)
                .fetchAll(db)
        }
    }

    func fetchByID(_ id: String) throws -> Snippet? {
        try dbQueue.read { db in
            try Snippet.fetchOne(db, key: id)
        }
    }

    func fetchByKeyword(_ keyword: String) throws -> Snippet? {
        try dbQueue.read { db in
            try Snippet
                .filter(Column("keyword") == keyword)
                .filter(Column("isDeleted") == false)
                .fetchOne(db)
        }
    }

    func fetchTrash() throws -> [Snippet] {
        try dbQueue.read { db in
            try Snippet
                .filter(Column("isDeleted") == true)
                .order(Column("deletedAt").desc)
                .fetchAll(db)
        }
    }

    /// 子串搜索（对 CJK 友好，不依赖 FTS5 分词）；不管可见性，隐藏条目也能按标题/
    /// 触发词/标签搜到（加密隐藏的 plainContent 在数据库里本就是 NULL，所以搜不到
    /// 密文对应的明文内容，只能搜到标题等元数据——这是内容层面隐藏的安全边界）。
    func search(_ query: String) throws -> [Snippet] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return try fetchActive() }

        let pattern = "%\(Self.escapeLikePattern(trimmed))%"
        return try dbQueue.read { db in
            try Snippet.fetchAll(
                db,
                sql: """
                    SELECT * FROM snippet
                    WHERE isDeleted = 0
                    AND (
                        name LIKE ? ESCAPE '\\'
                        OR keyword LIKE ? ESCAPE '\\'
                        OR plainContent LIKE ? ESCAPE '\\'
                        OR tags LIKE ? ESCAPE '\\'
                    )
                    ORDER BY updatedAt DESC, rowid DESC
                    """,
                arguments: [pattern, pattern, pattern, pattern]
            )
        }
    }

    private static func escapeLikePattern(_ input: String) -> String {
        input
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    /// 记录一次"使用"（全局热键浮层里被选中粘贴），不影响 updatedAt（那个只反映内容编辑）。
    func recordUsage(id: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE snippet SET usageCount = usageCount + 1, lastUsedAt = ? WHERE id = ?",
                arguments: [Date(), id]
            )
        }
    }

    func isKeywordAvailable(_ keyword: String, excludingID: String?) throws -> Bool {
        try dbQueue.read { db in
            var request = Snippet
                .filter(Column("keyword") == keyword)
                .filter(Column("isDeleted") == false)
            if let excludingID {
                request = request.filter(Column("id") != excludingID)
            }
            return try request.fetchCount(db) == 0
        }
    }
}
