import XCTest
import GRDB
@testable import ClipPower

@MainActor
final class ClipboardHistoryViewModelTests: XCTestCase {
    private func makeStore() throws -> ClipboardHistoryStore {
        let dbQueue = try DatabaseQueue()
        _ = DatabaseManager(dbQueue: dbQueue)
        return ClipboardHistoryStore(dbQueue: dbQueue)
    }

    private func text(_ value: String) -> ClipboardHistoryItem {
        ClipboardHistoryItem(kind: .text, textContent: value)
    }

    func testReassigningSameSearchTextDoesNotResetSelection() throws {
        let store = try makeStore()
        _ = try store.record(text("apple"))
        _ = try store.record(text("banana"))

        let viewModel = ClipboardHistoryViewModel(store: store)
        viewModel.searchText = "a"
        XCTAssertEqual(viewModel.results.count, 2)

        viewModel.moveSelection(by: 1)
        XCTAssertEqual(viewModel.selectedIndex, 1)

        viewModel.searchText = "a" // 模拟回车时重复提交同样的文本
        XCTAssertEqual(viewModel.selectedIndex, 1)
    }

    func testConfirmSelectionPastesHighlightedRow() throws {
        let store = try makeStore()
        _ = try store.record(text("apple"))
        _ = try store.record(text("banana"))

        let viewModel = ClipboardHistoryViewModel(store: store)
        viewModel.moveSelection(by: 1)
        let expected = viewModel.results[1]

        var pasted: ClipboardHistoryItem?
        viewModel.onPaste = { pasted = $0 }
        viewModel.confirmSelection()

        XCTAssertEqual(pasted, expected)
    }

    func testClearAllEmptiesResults() throws {
        let store = try makeStore()
        _ = try store.record(text("apple"))

        let viewModel = ClipboardHistoryViewModel(store: store)
        XCTAssertEqual(viewModel.results.count, 1)

        viewModel.clearAll()

        XCTAssertTrue(viewModel.results.isEmpty)
    }
}
