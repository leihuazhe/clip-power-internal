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

    /// 回归测试：`groupedResults` 里每一行携带的下标，必须真的指回 `results` 的同一项。
    /// 这条不变量以前是由视图里的 `results.firstIndex(of: item) ?? 0` 临时反查来保证的，
    /// 反查失败时 `?? 0` 会让多行都算成"第 0 项"——表现为多行同时高亮、
    /// 且点击/回车粘贴的永远是第一项。现在下标和元素在同一次快照里绑定，不可能错位。
    func testGroupedResultsCarryIndicesThatMatchResults() throws {
        let store = try makeStore()
        let calendar = Calendar.current
        let now = Date()
        // 故意跨越多个日期分组（今天/昨天/更早），确保分组不会破坏下标映射。
        for (offset, value) in [(0, "today-a"), (0, "today-b"), (-1, "yesterday"), (-40, "older")] {
            var item = text(value)
            item.createdAt = calendar.date(byAdding: .day, value: offset, to: now)!
            try store.dbQueue.write { try item.insert($0) }
        }

        let viewModel = ClipboardHistoryViewModel(store: store)
        XCTAssertEqual(viewModel.results.count, 4)
        XCTAssertGreaterThan(viewModel.groupedResults.count, 1, "应该真的分成了多个日期组")

        let allRows = viewModel.groupedResults.flatMap(\.items)
        XCTAssertEqual(allRows.count, viewModel.results.count, "分组不应丢项或重复项")
        XCTAssertEqual(Set(allRows.map(\.index)).count, allRows.count, "下标必须唯一，不能多行共用同一个")

        for row in allRows {
            XCTAssertEqual(
                viewModel.results[row.index], row.element,
                "下标 \(row.index) 指向的应该正是这一行自己的内容"
            )
        }
    }

    /// 回车粘贴后，那一条应该被排到列表最前面（下次呼出浮层重新查时体现出来）。
    func testConfirmSelectionMovesPastedItemToFront() throws {
        let store = try makeStore()
        _ = try store.record(text("apple"))
        Thread.sleep(forTimeInterval: 0.01)
        _ = try store.record(text("banana"))
        Thread.sleep(forTimeInterval: 0.01)
        _ = try store.record(text("cherry"))

        let viewModel = ClipboardHistoryViewModel(store: store)
        XCTAssertEqual(viewModel.results.first?.textContent, "cherry", "前置条件：最新的排最前")

        // 选到最后一条（最旧的 apple）并粘贴
        viewModel.moveSelection(by: 2)
        let pastedContent = viewModel.results[viewModel.selectedIndex].textContent
        XCTAssertEqual(pastedContent, "apple")
        Thread.sleep(forTimeInterval: 0.01)
        viewModel.confirmSelection()

        // 浮层下次呼出会 reset → reload，这里直接 reload 模拟
        viewModel.reload()
        XCTAssertEqual(viewModel.results.first?.textContent, "apple", "刚粘贴过的应该排到最前面")
        XCTAssertEqual(viewModel.results.count, 3, "只是重排，不应该新增记录")
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
