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
    /// 分组结果**缓存成存储属性**，只在 `results` 变化时重算一次。
    ///
    /// 之前它是计算属性，而 SwiftUI 的 body 在**任何** `@Published` 变化时都会重算——
    /// 包括每按一次方向键改 `selectedIndex`。于是每次按键都要把全部（实测 192）条
    /// 重新分一遍桶，按住方向键连按时明显卡顿。分组只取决于 `results`，和选中项无关，
    /// 所以缓存是等价的，按键路径上的成本从 O(n × 日期计算) 降到 0。
    @Published private(set) var groupedResults: [RowSection<ClipboardHistoryItem>] = []
    @Published var selectedIndex: Int = 0
    /// 见 `QuickPanelViewModel.focusToken` 的注释：同一套 `FloatingPanel.onBecomeKey`
    /// 确定性兜底聚焦机制。
    @Published private(set) var focusToken = 0

    private let store: ClipboardHistoryStore

    var onPaste: ((ClipboardHistoryItem) -> Void)?
    var onDismiss: (() -> Void)?

    init(store: ClipboardHistoryStore) {
        self.store = store
        reload()
    }

    func reload() {
        results = (try? store.search(searchText)) ?? []
        // 分组按"今天/昨天/本月/更早"打标签，`results` 已经按时间倒序，不重新排序。
        // 每项都带上它在 `results` 里的真实下标，视图不需要（也不允许）再反查——
        // 原因见 `IndexedRow` 的注释。
        groupedResults = DateSectionGrouping.grouped(results.indexedRows, dateForItem: { $0.element.createdAt })
        selectedIndex = 0
    }

    var selectedItem: ClipboardHistoryItem? {
        results.indices.contains(selectedIndex) ? results[selectedIndex] : nil
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
        let item = results[selectedIndex]
        // 用过就排到最前面（对标 `QuickPanelViewModel` 里粘贴片段时记 usage 的做法）。
        // 这里不顺手 reload：粘贴的同时浮层就关掉了，下次呼出走 `reset()` 会重新查一遍，
        // 没必要在关闭瞬间白拉一次全量数据。
        try? store.touch(id: item.id)
        onPaste?(item)
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

    func requestFocus() {
        focusToken += 1
    }
}
