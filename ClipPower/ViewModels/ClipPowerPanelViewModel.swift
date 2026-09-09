import Foundation
import Combine

enum ClipPowerPanelTab: Hashable {
    case snippets
    case clipboardHistory

    var title: String {
        switch self {
        case .snippets: return String(localized: "片段")
        case .clipboardHistory: return String(localized: "剪贴板历史")
        }
    }
}

/// 合并浮层的编排层：持有两个独立的子 ViewModel（各自的搜索状态互不干扰），
/// 只负责当前激活哪个 Tab、把方向键路由给当前 Tab 对应的子 ViewModel。
@MainActor
final class ClipPowerPanelViewModel: ObservableObject {
    @Published var activeTab: ClipPowerPanelTab = .snippets

    let snippetsViewModel: QuickPanelViewModel
    let clipboardHistoryViewModel: ClipboardHistoryViewModel

    init(snippetsViewModel: QuickPanelViewModel, clipboardHistoryViewModel: ClipboardHistoryViewModel) {
        self.snippetsViewModel = snippetsViewModel
        self.clipboardHistoryViewModel = clipboardHistoryViewModel
    }

    func cycleTab() {
        activeTab = (activeTab == .snippets) ? .clipboardHistory : .snippets
    }

    func moveSelection(by delta: Int) {
        switch activeTab {
        case .snippets:
            snippetsViewModel.moveSelection(by: delta)
        case .clipboardHistory:
            clipboardHistoryViewModel.moveSelection(by: delta)
        }
    }

    /// 回车确认（由 `FloatingPanel` 的窗口级按键监听路由过来，不走搜索框的 `.onSubmit`）。
    func confirmSelection() {
        switch activeTab {
        case .snippets:
            snippetsViewModel.confirmSelection()
        case .clipboardHistory:
            clipboardHistoryViewModel.confirmSelection()
        }
    }

    /// 面板重新打开时调用：定位到指定 Tab，并把两个子 ViewModel 的搜索状态都重置。
    func present(defaultTab: ClipPowerPanelTab) {
        activeTab = defaultTab
        snippetsViewModel.reset()
        clipboardHistoryViewModel.reset()
    }
}
