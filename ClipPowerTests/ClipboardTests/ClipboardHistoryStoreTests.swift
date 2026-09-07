import XCTest
import GRDB
@testable import ClipPower

final class ClipboardHistoryStoreTests: XCTestCase {
    private func makeStore(maxEntries: Int = 200) throws -> ClipboardHistoryStore {
        let dbQueue = try DatabaseQueue()
        _ = DatabaseManager(dbQueue: dbQueue)
        return ClipboardHistoryStore(dbQueue: dbQueue, maxEntries: maxEntries)
    }

    func testRecordAndFetchRecent() throws {
        let store = try makeStore()
        _ = try store.record("first")
        _ = try store.record("second")

        let recent = try store.fetchRecent()
        XCTAssertEqual(recent.count, 2)
        XCTAssertEqual(recent.first?.content, "second", "最新的应该排在最前面")
    }

    func testRecordSkipsConsecutiveDuplicate() throws {
        let store = try makeStore()
        XCTAssertTrue(try store.record("same"))
        XCTAssertFalse(try store.record("same"), "和上一条完全相同应该被跳过")

        XCTAssertEqual(try store.count(), 1)
    }

    func testRecordAllowsDuplicateIfNotConsecutive() throws {
        let store = try makeStore()
        _ = try store.record("a")
        _ = try store.record("b")
        _ = try store.record("a")

        XCTAssertEqual(try store.count(), 3)
    }

    func testRecordIgnoresEmptyContent() throws {
        let store = try makeStore()
        XCTAssertFalse(try store.record(""))
        XCTAssertEqual(try store.count(), 0)
    }

    func testOverCapacityPrunesOldestEntries() throws {
        let store = try makeStore(maxEntries: 3)
        for index in 1...5 {
            _ = try store.record("item-\(index)")
        }

        let all = try store.fetchRecent()
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(Set(all.map(\.content)), ["item-3", "item-4", "item-5"])
    }

    func testSearchMatchesSubstring() throws {
        let store = try makeStore()
        _ = try store.record("hello world")
        _ = try store.record("goodbye")

        let results = try store.search("world")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.content, "hello world")
    }

    func testDeleteRemovesSingleItem() throws {
        let store = try makeStore()
        _ = try store.record("keep")
        _ = try store.record("remove")
        let toDelete = try store.fetchRecent().first { $0.content == "remove" }!

        try store.delete(id: toDelete.id)

        let remaining = try store.fetchRecent()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.content, "keep")
    }

    func testClearAllRemovesEverything() throws {
        let store = try makeStore()
        _ = try store.record("a")
        _ = try store.record("b")

        try store.clearAll()

        XCTAssertEqual(try store.count(), 0)
    }
}
