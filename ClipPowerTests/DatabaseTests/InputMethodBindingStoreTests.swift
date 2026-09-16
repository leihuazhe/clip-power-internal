import XCTest
import GRDB
@testable import ClipPower

final class InputMethodBindingStoreTests: XCTestCase {
    private func makeStore() throws -> InputMethodBindingStore {
        let dbQueue = try DatabaseQueue()
        _ = DatabaseManager(dbQueue: dbQueue)
        return InputMethodBindingStore(dbQueue: dbQueue)
    }

    func testCreateAndFetchAll() throws {
        let store = try makeStore()
        _ = try store.create(InputMethodBinding(inputSourceID: "com.apple.inputmethod.SCIM.ITABC", displayName: "拼音"))

        let all = try store.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.displayName, "拼音")
    }

    func testFetchAllOrderedBySortOrder() throws {
        let store = try makeStore()
        _ = try store.create(InputMethodBinding(inputSourceID: "b", displayName: "B", sortOrder: 1))
        _ = try store.create(InputMethodBinding(inputSourceID: "a", displayName: "A", sortOrder: 0))

        let all = try store.fetchAll()
        XCTAssertEqual(all.map(\.displayName), ["A", "B"])
    }

    func testDeleteRemovesBinding() throws {
        let store = try makeStore()
        let created = try store.create(InputMethodBinding(inputSourceID: "a", displayName: "A"))

        try store.delete(id: created.id)

        XCTAssertTrue(try store.fetchAll().isEmpty)
    }

    func testShortcutNameIsDerivedFromIDNotInputSourceID() throws {
        let store = try makeStore()
        let created = try store.create(
            InputMethodBinding(inputSourceID: "com.apple.inputmethod.SCIM.ITABC", displayName: "拼音")
        )

        XCTAssertEqual(created.shortcutName.rawValue, "inputMethodHotkey_\(created.id)")
        XCTAssertFalse(created.shortcutName.rawValue.contains("."))
    }

    func testChangeNotificationPostedOnCreateAndDelete() throws {
        let store = try makeStore()
        var changeCount = 0
        let observer = NotificationCenter.default.addObserver(
            forName: .inputMethodBindingsDidChange, object: nil, queue: nil
        ) { _ in
            changeCount += 1
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let created = try store.create(InputMethodBinding(inputSourceID: "a", displayName: "A"))
        try store.delete(id: created.id)

        XCTAssertEqual(changeCount, 2)
    }
}
