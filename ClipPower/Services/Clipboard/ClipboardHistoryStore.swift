import Foundation
import GRDB

/// 剪贴板历史的 CRUD；不做任何加密/隐藏——那是 Snippets 的特性，
/// 剪贴板历史就是原始系统剪贴板内容的滚动记录，对标 Raycast 的 Clipboard History。
final class ClipboardHistoryStore: Sendable {
    let dbQueue: DatabaseQueue
    private let maxEntries: Int

    init(dbQueue: DatabaseQueue, maxEntries: Int = 200) {
        self.dbQueue = dbQueue
        self.maxEntries = maxEntries
    }

    /// 记录一条新内容；如果和最近一条完全相同则跳过（避免重复复制/自身粘贴写回剪贴板造出重复记录）。
    /// 超过容量上限时清理最旧的条目。
    @discardableResult
    func record(_ content: String) throws -> Bool {
        guard !content.isEmpty else { return false }

        return try dbQueue.write { db in
            // 用 rowid 做次级排序键：createdAt 精度不足以区分同一毫秒内的多次写入
            // （测试里连续 record() 几乎总是撞到这个问题），rowid 能保证反映真实插入顺序。
            if let mostRecent = try ClipboardHistoryItem
                .order(Column("createdAt").desc, Column("rowid").desc)
                .fetchOne(db), mostRecent.content == content {
                return false
            }

            try ClipboardHistoryItem(content: content).insert(db)

            let count = try ClipboardHistoryItem.fetchCount(db)
            if count > self.maxEntries {
                let overflow = count - self.maxEntries
                try db.execute(
                    sql: """
                        DELETE FROM clipboardHistoryItem WHERE id IN (
                            SELECT id FROM clipboardHistoryItem ORDER BY createdAt ASC, rowid ASC LIMIT ?
                        )
                        """,
                    arguments: [overflow]
                )
            }
            return true
        }
    }

    func fetchRecent(limit: Int = 200) throws -> [ClipboardHistoryItem] {
        try dbQueue.read { db in
            try ClipboardHistoryItem
                .order(Column("createdAt").desc, Column("rowid").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func count() throws -> Int {
        try dbQueue.read { db in try ClipboardHistoryItem.fetchCount(db) }
    }

    func search(_ query: String) throws -> [ClipboardHistoryItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return try fetchRecent() }

        let pattern = "%\(Self.escapeLikePattern(trimmed))%"
        return try dbQueue.read { db in
            try ClipboardHistoryItem.fetchAll(
                db,
                sql: "SELECT * FROM clipboardHistoryItem WHERE content LIKE ? ESCAPE '\\' ORDER BY createdAt DESC, rowid DESC",
                arguments: [pattern]
            )
        }
    }

    func delete(id: String) throws {
        try dbQueue.write { db in
            _ = try ClipboardHistoryItem.deleteOne(db, key: id)
        }
    }

    func clearAll() throws {
        try dbQueue.write { db in
            _ = try ClipboardHistoryItem.deleteAll(db)
        }
    }

    private static func escapeLikePattern(_ input: String) -> String {
        input
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }
}
