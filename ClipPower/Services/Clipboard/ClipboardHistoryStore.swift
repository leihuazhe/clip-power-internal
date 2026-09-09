import Foundation
import GRDB

/// 剪贴板历史的 CRUD；不做任何加密/隐藏——那是 Snippets 的特性，
/// 剪贴板历史就是原始系统剪贴板内容的滚动记录，对标 Raycast 的 Clipboard History。
/// 支持文本/图片/文件三种类型。
final class ClipboardHistoryStore: Sendable {
    let dbQueue: DatabaseQueue
    private let maxEntries: Int

    init(dbQueue: DatabaseQueue, maxEntries: Int = 200) {
        self.dbQueue = dbQueue
        self.maxEntries = maxEntries
    }

    /// 记录一条新内容。如果历史里**任何位置**已经存在完全相同的内容（同类型：文本比
    /// 文字、图片比字节、文件比路径列表），不会新建重复记录，而是直接把已有那条的
    /// 时间戳更新成现在——效果就是"挪到最前面"，避免同一份内容中间隔了别的复制
    /// 操作后又被记一遍，在列表里堆出一堆重复项。超过容量上限时清理最旧的条目。
    @discardableResult
    func record(_ draft: ClipboardHistoryItem) throws -> Bool {
        guard Self.hasRecordableContent(draft) else { return false }

        return try dbQueue.write { db in
            let sameKindItems = try ClipboardHistoryItem
                .filter(Column("kind") == draft.kind.rawValue)
                .fetchAll(db)

            if let existing = sameKindItems.first(where: { Self.isDuplicate($0, draft) }) {
                try db.execute(
                    sql: "UPDATE clipboardHistoryItem SET createdAt = ? WHERE id = ?",
                    arguments: [Date(), existing.id]
                )
                return false
            }

            var item = draft
            item.id = UUID().uuidString
            item.createdAt = Date()
            try item.insert(db)

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

    private static func hasRecordableContent(_ item: ClipboardHistoryItem) -> Bool {
        switch item.kind {
        case .text:
            return !(item.textContent ?? "").isEmpty
        case .image:
            return item.imageData != nil
        case .file:
            return !item.fileURLs.isEmpty
        }
    }

    private static func isDuplicate(_ existing: ClipboardHistoryItem, _ draft: ClipboardHistoryItem) -> Bool {
        guard existing.kind == draft.kind else { return false }
        switch draft.kind {
        case .text:
            return existing.textContent == draft.textContent
        case .image:
            return existing.imageData == draft.imageData
        case .file:
            return existing.fileURLs == draft.fileURLs
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

    /// 子串搜索：文本内容 / 文件名（fileURLs 的 JSON 文本里搜）；图片没有可搜索的文字，
    /// 只会出现在不带搜索词的浏览列表里。
    func search(_ query: String) throws -> [ClipboardHistoryItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return try fetchRecent() }

        let pattern = "%\(Self.escapeLikePattern(trimmed))%"
        return try dbQueue.read { db in
            try ClipboardHistoryItem.fetchAll(
                db,
                sql: """
                    SELECT * FROM clipboardHistoryItem
                    WHERE textContent LIKE ? ESCAPE '\\' OR fileURLs LIKE ? ESCAPE '\\'
                    ORDER BY createdAt DESC, rowid DESC
                    """,
                arguments: [pattern, pattern]
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
