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
    @Published var selectedIndex: Int = 0
    @Published private(set) var isRevealing = false
    @Published var errorMessage: String?

    private let store: SnippetStore
    private let encryptionService: SnippetEncryptionService

    /// 由 AppDelegate 注入：确认粘贴文本 / 关闭浮层。
    var onPaste: ((String) -> Void)?
    var onDismiss: (() -> Void)?

    init(store: SnippetStore, encryptionService: SnippetEncryptionService = SnippetEncryptionService()) {
        self.store = store
        self.encryptionService = encryptionService
        reload()
    }

    func reload() {
        // 隐藏条目也会出现在结果里（标题/关键词可搜到），只是内容打码；
        // 加密隐藏的 plainContent 在数据库里本就是 NULL，所以搜不到密文对应的明文。
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
        case .normal, .softHidden:
            if let content = snippet.plainContent {
                onPaste?(content)
            }
        case .encryptedHidden:
            isRevealing = true
            do {
                let content = try await encryptionService.reveal(snippet)
                isRevealing = false
                onPaste?(content)
            } catch {
                isRevealing = false
                errorMessage = "验证失败：\(error.localizedDescription)"
            }
        }
    }
}
