import XCTest
import GRDB
@testable import ClipPower

final class SnippetStoreTests: XCTestCase {
    private func makeStore() throws -> SnippetStore {
        let dbQueue = try DatabaseQueue()
        _ = DatabaseManager(dbQueue: dbQueue)
        return SnippetStore(dbQueue: dbQueue)
    }

    func testCreateAndFetchActive() throws {
        let store = try makeStore()
        _ = try store.create(Snippet(name: "地址", keyword: "addr", plainContent: "123 Main St"))

        let active = try store.fetchActive()
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active.first?.name, "地址")
    }

    func testCreateDuplicateKeywordThrows() throws {
        let store = try makeStore()
        _ = try store.create(Snippet(name: "A", keyword: "dup", plainContent: "a"))

        XCTAssertThrowsError(try store.create(Snippet(name: "B", keyword: "dup", plainContent: "b"))) { error in
            XCTAssertEqual(error as? SnippetStoreError, .duplicateKeyword)
        }
    }

    func testUpdateChangesContentAndBumpsUpdatedAt() throws {
        let store = try makeStore()
        let created = try store.create(Snippet(name: "A", plainContent: "old"))

        var edited = created
        edited.plainContent = "new"
        let updated = try store.update(edited)

        XCTAssertEqual(updated.plainContent, "new")
        XCTAssertGreaterThanOrEqual(updated.updatedAt, created.updatedAt)
    }

    func testSoftDeleteMovesToTrashAndOutOfActive() throws {
        let store = try makeStore()
        let created = try store.create(Snippet(name: "A"))

        try store.softDelete(id: created.id)

        XCTAssertTrue(try store.fetchActive().isEmpty)
        let trash = try store.fetchTrash()
        XCTAssertEqual(trash.count, 1)
        XCTAssertEqual(trash.first?.id, created.id)
    }

    func testRestoreBringsBackToActive() throws {
        let store = try makeStore()
        let created = try store.create(Snippet(name: "A"))
        try store.softDelete(id: created.id)

        try store.restore(id: created.id)

        XCTAssertEqual(try store.fetchActive().count, 1)
        XCTAssertTrue(try store.fetchTrash().isEmpty)
    }

    func testPermanentlyDeleteRemovesRow() throws {
        let store = try makeStore()
        let created = try store.create(Snippet(name: "A"))
        try store.softDelete(id: created.id)

        try store.permanentlyDelete(id: created.id)

        XCTAssertTrue(try store.fetchTrash().isEmpty)
    }

    func testPurgeExpiredTrashOnlyRemovesOldEntries() throws {
        let store = try makeStore()
        let recent = try store.create(Snippet(name: "Recent"))
        let old = try store.create(Snippet(name: "Old"))

        try store.softDelete(id: recent.id)
        try store.softDelete(id: old.id)

        // 手动把 old 的 deletedAt 改到 40 天前，模拟已过期的回收站条目。
        let backdated = Date().addingTimeInterval(-40 * 86400)
        try store.dbQueue.write { db in
            try db.execute(sql: "UPDATE snippet SET deletedAt = ? WHERE id = ?", arguments: [backdated, old.id])
        }

        let purged = try store.purgeExpiredTrash(retentionDays: 30)

        XCTAssertEqual(purged, 1)
        let remainingTrash = try store.fetchTrash()
        XCTAssertEqual(remainingTrash.count, 1)
        XCTAssertEqual(remainingTrash.first?.id, recent.id)
    }

    func testSearchMatchesNameKeywordAndContent() throws {
        let store = try makeStore()
        _ = try store.create(Snippet(name: "工作邮箱", keyword: "workmail", plainContent: "me@company.com"))
        _ = try store.create(Snippet(name: "个人邮箱", keyword: "personalmail", plainContent: "me@gmail.com"))

        let byName = try store.search("工作")
        XCTAssertEqual(byName.count, 1)
        XCTAssertEqual(byName.first?.keyword, "workmail")

        let byContent = try store.search("gmail")
        XCTAssertEqual(byContent.count, 1)
        XCTAssertEqual(byContent.first?.keyword, "personalmail")
    }

    func testSearchDoesNotExposeEncryptedContentButFindsTitle() throws {
        let store = try makeStore()
        // 真实的加密隐藏条目 plainContent 必为 nil（内容只存在 cipherContent 里），
        // 这是"加密内容搜不到"的安全边界；但标题本身是隐藏条目也应该能被搜到的。
        _ = try store.create(Snippet(
            name: "密钥",
            plainContent: nil,
            cipherContent: Data("encrypted-blob-placeholder".utf8),
            visibility: .encryptedHidden
        ))

        let byContent = try store.search("topsecretvalue")
        XCTAssertTrue(byContent.isEmpty)

        let byName = try store.search("密钥")
        XCTAssertEqual(byName.count, 1)
    }

    func testFetchActiveIncludesHiddenSnippets() throws {
        let store = try makeStore()
        _ = try store.create(Snippet(name: "公开", visibility: .normal))
        _ = try store.create(Snippet(name: "软隐藏", visibility: .softHidden))
        _ = try store.create(Snippet(name: "加密隐藏", visibility: .encryptedHidden))

        let all = try store.fetchActive()

        XCTAssertEqual(all.count, 3)
        XCTAssertTrue(all.contains { $0.visibility == .softHidden })
        XCTAssertTrue(all.contains { $0.visibility == .encryptedHidden })
    }

    func testRecordUsageIncrementsCountAndSetsLastUsedAtWithoutTouchingUpdatedAt() throws {
        let store = try makeStore()
        let created = try store.create(Snippet(name: "A"))
        XCTAssertEqual(created.usageCount, 0)
        XCTAssertNil(created.lastUsedAt)

        try store.recordUsage(id: created.id)
        try store.recordUsage(id: created.id)

        let updated = try store.fetchActive().first { $0.id == created.id }
        XCTAssertEqual(updated?.usageCount, 2)
        XCTAssertNotNil(updated?.lastUsedAt)
        // 用小容差比较：GRDB 往返存储 Date 可能有亚毫秒级精度损失，不能用严格相等。
        let updatedAtDelta = abs((updated?.updatedAt ?? .distantPast).timeIntervalSince(created.updatedAt))
        XCTAssertLessThan(updatedAtDelta, 0.001, "使用记录不应该改变 updatedAt")
    }

    func testIsKeywordAvailable() throws {
        let store = try makeStore()
        let created = try store.create(Snippet(name: "A", keyword: "taken"))

        XCTAssertFalse(try store.isKeywordAvailable("taken", excludingID: nil))
        XCTAssertTrue(try store.isKeywordAvailable("taken", excludingID: created.id))
        XCTAssertTrue(try store.isKeywordAvailable("free", excludingID: nil))
    }
}
