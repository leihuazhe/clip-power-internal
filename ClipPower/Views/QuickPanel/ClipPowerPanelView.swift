import SwiftUI

/// 合并浮层：顶部一个 Tab 条（片段 / 剪贴板历史），下方按当前 Tab 切换显示对应内容。
/// 每个 Tab 各自保留自己的搜索框状态和选中项。
struct ClipPowerPanelView: View {
    @ObservedObject var viewModel: ClipPowerPanelViewModel

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            Group {
                switch viewModel.activeTab {
                case .snippets:
                    QuickPanelView(viewModel: viewModel.snippetsViewModel)
                case .clipboardHistory:
                    ClipboardHistoryView(viewModel: viewModel.clipboardHistoryViewModel)
                }
            }
        }
        .background(VisualEffectBackground())
        .frame(width: 820, height: 520)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var tabBar: some View {
        HStack(spacing: 8) {
            ForEach([ClipPowerPanelTab.clipboardHistory, .snippets], id: \.self) { tab in
                Text(tab.title)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(tab == viewModel.activeTab ? Color.accentColor.opacity(0.2) : Color.clear)
                    .foregroundStyle(tab == viewModel.activeTab ? Color.accentColor : Color.secondary)
                    .clipShape(Capsule())
                    .contentShape(Rectangle())
                    .onTapGesture { viewModel.activeTab = tab }
            }
            Spacer()
            Text("⇥ 切换标签").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 6, trailing: 12))
    }
}
