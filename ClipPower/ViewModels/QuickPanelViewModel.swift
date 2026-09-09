import Foundation
import Combine

@MainActor
final class QuickPanelViewModel: ObservableObject {
    @Published var searchText: String = "" {
        didSet {
            // 回车确认时，文本框会把当前文本"重新提交"一次给绑定值，即使内容没变也会
            // 触发 didSet；如果不做这个判断，reload() 会把刚用方向键选好的 selectedIndex
            // 归零，导致回车粘贴的是列表第一项而不是当前选中项。
            guard oldValue != searchText else { return }
            reload()
        }
    }
    @Published private(set) var results: [Snippet] = []
    /// 分组结果缓存成存储属性，只在 `results` 变化时重算——理由同
    /// `ClipboardHistoryViewModel.groupedResults` 的注释（计算属性会让每次按方向键
     /// 都把全部条目重新分一遍桶，连按时卡顿）。
    @Published private(set) var groupedResults: [RowSection<Snippet>] = []
    @Published var selectedIndex: Int = 0
    @Published private(set) var isRevealing = false
    @Published var errorMessage: String?

    private let store: SnippetStore
    private let encryptionService: SnippetEncryptionService

    /// 由 AppDelegate 注入：确认粘贴文本（含粘贴方式）/ 关闭浮层。
    var onPaste: ((String, PasteMethod) -> Void)?
    var onDismiss: (() -> Void)?

    init(store: SnippetStore, encryptionService: SnippetEncryptionService = SnippetEncryptionService()) {
        self.store = store
        self.encryptionService = encryptionService
        reload()
    }

    func reload() {
        // 隐藏条目也会出现在结果里（标题/关键词可搜到），只是内容打码；
        // 加密隐藏的 plainContent 在数据库里本就是 NULL，所以搜不到密文对应的明文。
        // 按最近使用时间排序（对标 Raycast），从没用过的按创建时间排。
        let fetched = (try? store.search(searchText)) ?? []
        // 用原始下标做兜底排序键，保证时间戳完全相同时排序结果依然稳定、可预测
        // （Swift 的 sorted(by:) 不保证稳定排序，光比时间戳在极端情况下会导致顺序抖动）。
        results = fetched.enumerated()
            .sorted { lhs, rhs in
                let lhsKey = lhs.element.lastUsedAt ?? lhs.element.createdAt
                let rhsKey = rhs.element.lastUsedAt ?? rhs.element.createdAt
                if lhsKey != rhsKey { return lhsKey > rhsKey }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
        // 按"今天/昨天/本月/更早"分组，组内顺序和 `results` 保持一致；每项都带上它在
        // `results` 里的真实下标，视图不需要（也不允许）再反查——见 `IndexedRow` 注释。
        groupedResults = DateSectionGrouping.grouped(
            results.indexedRows,
            dateForItem: { $0.element.lastUsedAt ?? $0.element.createdAt }
        )
        selectedIndex = 0
    }

    var selectedSnippet: Snippet? {
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
        let snippet = results[selectedIndex]
        Task {
            await paste(snippet)
        }
    }

    func dismiss() {
        onDismiss?()
    }

    func reset() {
        searchText = ""
        selectedIndex = 0
        errorMessage = nil
        reload()
    }

    private func paste(_ snippet: Snippet) async {
        switch snippet.visibility {
        case .normal:
            if let content = snippet.plainContent {
                try? store.recordUsage(id: snippet.id)
                onPaste?(content, .clipboard)
            }
        case .softHidden:
            // 软隐藏/加密隐藏都不走剪贴板：刚"解锁"的敏感内容一旦进了系统剪贴板，
            // 会被我们自己的 ClipboardMonitor（或用户机器上别的剪贴板管理器）
            // 又记录成一条明文历史，等于白隐藏了。直接模拟键盘输入，用一次就没了。
            if let content = snippet.plainContent {
                try? store.recordUsage(id: snippet.id)
                onPaste?(content, .direct)
            }
        case .encryptedHidden:
            isRevealing = true
            do {
                let content = try await encryptionService.reveal(snippet)
                isRevealing = false
                try? store.recordUsage(id: snippet.id)
                onPaste?(content, .direct)
            } catch {
                isRevealing = false
                errorMessage = localizedFormat("verificationFailedFormat", error.localizedDescription)
            }
        }
    }
}
