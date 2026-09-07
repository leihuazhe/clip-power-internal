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
        viewModel.onPaste = { text in
            pasted = text
            expectation.fulfill()
        }

        // 模拟真实按键顺序：↓ 选中第二项，再按回车（文本框重新提交同样的值），最后确认。
        viewModel.searchText = "d"
        viewModel.confirmSelection()

        await fulfillment(of: [expectation], timeout: 1)
        XCTAssertEqual(pasted, expectedContent)
    }
}
