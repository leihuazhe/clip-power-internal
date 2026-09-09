import XCTest
import GRDB
@testable import ClipPower

final class ClipboardHistoryStoreTests: XCTestCase {
    private func makeStore(maxEntries: Int = 200) throws -> ClipboardHistoryStore {
        let dbQueue = try DatabaseQueue()
        _ = DatabaseManager(dbQueue: dbQueue)
        return ClipboardHistoryStore(dbQueue: dbQueue, maxEntries: maxEntries)
    }

    private func text(_ value: String) -> ClipboardHistoryItem {
        ClipboardHistoryItem(kind: .text, textContent: value)
    }

    func testRecordAndFetchRecent() throws {
        let store = try makeStore()
        _ = try store.record(text("first"))
        _ = try store.record(text("second"))

        let recent = try store.fetchRecent()
        XCTAssertEqual(recent.count, 2)
        XCTAssertEqual(recent.first?.textContent, "second", "最新的应该排在最前面")
    }

    func testRecordSkipsConsecutiveDuplicate() throws {
        let store = try makeStore()
        XCTAssertTrue(try store.record(text("same")))
        XCTAssertFalse(try store.record(text("same")), "和上一条完全相同应该被跳过")

        XCTAssertEqual(try store.count(), 1)
    }

    func testRecordDeduplicatesEvenWhenNotConsecutive() throws {
        let store = try makeStore()
        _ = try store.record(text("a"))
        Thread.sleep(forTimeInterval: 0.01) // 避免时间戳精度打平导致排序断言不稳定
        _ = try store.record(text("b"))
        Thread.sleep(forTimeInterval: 0.01)
        _ = try store.record(text("a"))

        // "a" 中间隔了 "b" 又被复制了一次，不应该新建第三条，而是把已有的 "a" 挪到最前面。
        XCTAssertEqual(try store.count(), 2)
        let recent = try store.fetchRecent()
        XCTAssertEqual(recent.first?.textContent, "a", "重复内容应该被挪到最前面而不是新建")
    }

    func testRecordDuplicateBumpsExistingEntryToTop() throws {
        let store = try makeStore()
        let first = try recordAndFetch(store, "a")
        _ = try store.record(text("b"))

        Thread.sleep(forTimeInterval: 0.01) // 确保新的 createdAt 明显更晚
        _ = try store.record(text("a"))

        let updated = try store.fetchRecent().first { $0.textContent == "a" }!
        XCTAssertEqual(updated.id, first.id, "应该是同一条记录被更新，而不是新建了一条")
        XCTAssertGreaterThan(updated.createdAt, first.createdAt)
    }

    private func recordAndFetch(_ store: ClipboardHistoryStore, _ value: String) throws -> ClipboardHistoryItem {
        _ = try store.record(text(value))
        return try store.fetchRecent().first { $0.textContent == value }!
    }

    func testRecordIgnoresEmptyTextContent() throws {
        let store = try makeStore()
        XCTAssertFalse(try store.record(text("")))
        XCTAssertEqual(try store.count(), 0)
    }

    func testOverCapacityPrunesOldestEntries() throws {
        let store = try makeStore(maxEntries: 3)
        for index in 1...5 {
            _ = try store.record(text("item-\(index)"))
        }

        let all = try store.fetchRecent()
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(Set(all.map(\.textContent)), ["item-3", "item-4", "item-5"])
    }

    func testSearchMatchesSubstring() throws {
        let store = try makeStore()
        _ = try store.record(text("hello world"))
        _ = try store.record(text("goodbye"))

        let results = try store.search("world")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.textContent, "hello world")
    }

    func testDeleteRemovesSingleItem() throws {
        let store = try makeStore()
        _ = try store.record(text("keep"))
        _ = try store.record(text("remove"))
        let toDelete = try store.fetchRecent().first { $0.textContent == "remove" }!

        try store.delete(id: toDelete.id)

        let remaining = try store.fetchRecent()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.textContent, "keep")
    }

    func testClearAllRemovesEverything() throws {
        let store = try makeStore()
        _ = try store.record(text("a"))
        _ = try store.record(text("b"))

        try store.clearAll()

        XCTAssertEqual(try store.count(), 0)
    }

    // MARK: - 图片 / 文件类型

    func testRecordImageStoresDataAndDimensions() throws {
        let store = try makeStore()
        let data = Data([0x01, 0x02, 0x03])
        _ = try store.record(ClipboardHistoryItem(kind: .image, imageData: data, imageWidth: 100, imageHeight: 50, byteSize: data.count))

        let recent = try store.fetchRecent()
        XCTAssertEqual(recent.count, 1)
        XCTAssertEqual(recent.first?.kind, .image)
        XCTAssertEqual(recent.first?.imageData, data)
        XCTAssertEqual(recent.first?.imageWidth, 100)
        XCTAssertEqual(recent.first?.imageHeight, 50)
    }

    func testRecordFileStoresURLs() throws {
        let store = try makeStore()
        _ = try store.record(ClipboardHistoryItem(kind: .file, fileURLs: ["/tmp/a.txt", "/tmp/b.txt"], byteSize: 42))

        let recent = try store.fetchRecent()
        XCTAssertEqual(recent.first?.kind, .file)
        XCTAssertEqual(recent.first?.fileURLs, ["/tmp/a.txt", "/tmp/b.txt"])
        XCTAssertEqual(recent.first?.byteSize, 42)
    }

    func testDuplicateDetectionDoesNotCrossKinds() throws {
        let store = try makeStore()
        // 文本 "same" 和图片/文件即使"内容"字符串一样也不算重复（不同类型)。
        _ = try store.record(text("same"))
        _ = try store.record(ClipboardHistoryItem(kind: .file, fileURLs: ["same"]))

        XCTAssertEqual(try store.count(), 2)
    }

    func testSearchFindsFileByName() throws {
        let store = try makeStore()
        _ = try store.record(ClipboardHistoryItem(kind: .file, fileURLs: ["/Users/a/report.pdf"]))
        _ = try store.record(ClipboardHistoryItem(kind: .image, imageData: Data([0x00])))

        let results = try store.search("report")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.kind, .file)
    }
}
