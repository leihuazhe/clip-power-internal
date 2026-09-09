import XCTest
import GRDB
@testable import ClipPower

@MainActor
final class QuickPanelViewModelTests: XCTestCase {
    private func makeStore() throws -> SnippetStore {
        let dbQueue = try DatabaseQueue()
        _ = DatabaseManager(dbQueue: dbQueue)
        return SnippetStore(dbQueue: dbQueue)
    }

    /// 回归测试：回车确认时，文本框会把当前文本"重新提交"一次给绑定的 searchText，
    /// 即使内容没变。如果 didSet 不做变化判断就无条件 reload()，会把用户刚用方向键
    /// 选好的 selectedIndex 归零，导致回车粘贴的是列表第一项而不是当前选中项。
    func testReassigningSameSearchTextDoesNotResetSelection() throws {
        let store = try makeStore()
        _ = try store.create(Snippet(name: "asdf"))
        _ = try store.create(Snippet(name: "pwddd"))

        let viewModel = QuickPanelViewModel(store: store)
        viewModel.searchText = "d"
        XCTAssertEqual(viewModel.results.count, 2)

        viewModel.moveSelection(by: 1)
        XCTAssertEqual(viewModel.selectedIndex, 1)

        // 模拟按回车时文本框把当前文本重新提交一次（值没变）。
        viewModel.searchText = "d"

        XCTAssertEqual(viewModel.selectedIndex, 1, "重复赋值同样的搜索文本不应该重置选中项")
    }

    func testChangingSearchTextResetsSelection() throws {
        let store = try makeStore()
        _ = try store.create(Snippet(name: "asdf"))
        _ = try store.create(Snippet(name: "pwddd"))

        let viewModel = QuickPanelViewModel(store: store)
        viewModel.searchText = "d"
        viewModel.moveSelection(by: 1)
        XCTAssertEqual(viewModel.selectedIndex, 1)

        viewModel.searchText = "pwddd"

        XCTAssertEqual(viewModel.selectedIndex, 0, "搜索词真的变化时应该重置到第一项")
    }

    func testConfirmSelectionPastesHighlightedRowNotFirstRow() async throws {
        let store = try makeStore()
        _ = try store.create(Snippet(name: "asdf", plainContent: "asdf-content"))
        _ = try store.create(Snippet(name: "pwddd", plainContent: "pwddd-content"))

        let viewModel = QuickPanelViewModel(store: store)
        viewModel.searchText = "d"
        viewModel.moveSelection(by: 1)
        let expectedContent = viewModel.results[1].plainContent

        var pasted: String?
        let expectation = expectation(description: "paste")
        viewModel.onPaste = { text, _ in
            pasted = text
            expectation.fulfill()
        }

        // 模拟真实按键顺序：↓ 选中第二项，再按回车（文本框重新提交同样的值），最后确认。
        viewModel.searchText = "d"
        viewModel.confirmSelection()

        await fulfillment(of: [expectation], timeout: 1)
        XCTAssertEqual(pasted, expectedContent)
    }

    func testPastingBumpsRecentlyUsedItemToTop() async throws {
        let store = try makeStore()
        let older = try store.create(Snippet(name: "older", plainContent: "older-content"))
        let newer = try store.create(Snippet(name: "newer", plainContent: "newer-content"))

        // 两次 create() 之间隔的时间太短，真实时钟精度可能分不出先后（尤其是在测试
        // 套件整体运行、系统负载较高时）。把两条记录的时间都往前拨、拉开一整天的
        // 差距，这样后面 recordUsage() 写入的真实"现在"时间必然明显晚于 newer 的
        // 固定创建时间，不会再撞上时钟精度导致的平局。
        let now = Date()
        let olderBackdated = now.addingTimeInterval(-2 * 86400)
        let newerBackdated = now.addingTimeInterval(-86400)
        try await store.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE snippet SET createdAt = ?, updatedAt = ? WHERE id = ?",
                arguments: [olderBackdated, olderBackdated, older.id]
            )
            try db.execute(
                sql: "UPDATE snippet SET createdAt = ?, updatedAt = ? WHERE id = ?",
                arguments: [newerBackdated, newerBackdated, newer.id]
            )
        }

        let viewModel = QuickPanelViewModel(store: store)
        // "newer" 创建时间更晚，应该排在最前面。
        XCTAssertEqual(viewModel.results.first?.name, "newer")

        // 手动选中并粘贴 older（模拟用户用了它一次）。
        let olderIndex = viewModel.results.firstIndex { $0.id == older.id }!
        viewModel.selectRow(at: olderIndex)

        let expectation = expectation(description: "paste")
        viewModel.onPaste = { _, _ in expectation.fulfill() }
        viewModel.confirmSelection()
        await fulfillment(of: [expectation], timeout: 1)

        viewModel.reload()
        XCTAssertEqual(viewModel.results.first?.name, "older", "刚被使用过的片段应该排到最前面")
    }

    func testNormalSnippetPastesViaClipboard() async throws {
        let store = try makeStore()
        _ = try store.create(Snippet(name: "normal", plainContent: "normal-content", visibility: .normal))

        let viewModel = QuickPanelViewModel(store: store)
        var usedMethod: PasteMethod?
        let expectation = expectation(description: "paste")
        viewModel.onPaste = { _, method in
            usedMethod = method
            expectation.fulfill()
        }

        viewModel.confirmSelection()
        await fulfillment(of: [expectation], timeout: 1)

        XCTAssertEqual(usedMethod, .clipboard)
    }

    func testSoftHiddenSnippetPastesDirectlyNotViaClipboard() async throws {
        let store = try makeStore()
        _ = try store.create(Snippet(name: "soft", plainContent: "soft-content", visibility: .softHidden))

        let viewModel = QuickPanelViewModel(store: store)
        var usedMethod: PasteMethod?
        let expectation = expectation(description: "paste")
        viewModel.onPaste = { _, method in
            usedMethod = method
            expectation.fulfill()
        }

        viewModel.confirmSelection()
        await fulfillment(of: [expectation], timeout: 1)

        XCTAssertEqual(usedMethod, .direct, "软隐藏内容不应该经过剪贴板")
    }

    func testGroupedResultsBucketsAllTodayItemsTogether() throws {
        let store = try makeStore()
        _ = try store.create(Snippet(name: "a"))
        _ = try store.create(Snippet(name: "b"))

        let viewModel = QuickPanelViewModel(store: store)

        XCTAssertEqual(viewModel.groupedResults.count, 1)
        XCTAssertEqual(viewModel.groupedResults.first?.title, "今天")
        XCTAssertEqual(viewModel.groupedResults.first?.items.count, 2)
    }
}
