import Foundation
import Combine

@MainActor
final class ClipboardHistoryViewModel: ObservableObject {
    @Published var searchText: String = "" {
        didSet {
            // 见 QuickPanelViewModel 里同样的注释：回车确认时文本框会把当前文本
            // 重新提交一次，即使内容没变，不加这个判断会把选中项冲掉。
            guard oldValue != searchText else { return }
            reload()
        }
    }
    @Published private(set) var results: [ClipboardHistoryItem] = []
    @Published var selectedIndex: Int = 0

    private let store: ClipboardHistoryStore

    var onPaste: ((String) -> Void)?
    var onDismiss: (() -> Void)?

    init(store: ClipboardHistoryStore) {
        self.store = store
        reload()
    }

    func reload() {
        results = (try? store.search(searchText)) ?? []
        selectedIndex = 0
    }

    func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = max(0, min(results.count - 1, selectedIndex + delta))
    }

    func selectRow(at index: Int) {
        guard results.indices.contains(index) else { return }
        selectedIndex = index
    }

    func confirmSelection() {
        guard results.indices.contains(selectedIndex) else { return }
        onPaste?(results[selectedIndex].content)
    }

    func delete(_ item: ClipboardHistoryItem) {
        try? store.delete(id: item.id)
        reload()
    }

    func clearAll() {
        try? store.clearAll()
        reload()
    }

    func dismiss() {
        onDismiss?()
    }

    func reset() {
        searchText = ""
        selectedIndex = 0
        reload()
    }
}
