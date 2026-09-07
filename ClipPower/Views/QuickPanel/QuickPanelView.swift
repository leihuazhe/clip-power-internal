import SwiftUI
import AppKit

struct QuickPanelView: View {
    @ObservedObject var viewModel: QuickPanelViewModel
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索片段...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($isSearchFocused)
                    .onSubmit { viewModel.confirmSelection() }
            }
            .padding(14)

            Divider()

            if viewModel.results.isEmpty {
                Spacer()
                Text("没有匹配的片段")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(viewModel.results.enumerated()), id: \.element.id) { index, snippet in
                            QuickPanelRow(snippet: snippet, isSelected: index == viewModel.selectedIndex)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    viewModel.selectRow(at: index)
                                    viewModel.confirmSelection()
                                }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }

            Divider()
            HStack(spacing: 12) {
                Text("↩ 选择").font(.caption2).foregroundStyle(.secondary)
                Text("↑↓ 切换").font(.caption2).foregroundStyle(.secondary)
                Text("Esc 关闭").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if viewModel.isRevealing {
                    ProgressView().controlSize(.small)
                    Text("验证中...").font(.caption2).foregroundStyle(.secondary)
                } else if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage).font(.caption2).foregroundStyle(.red)
                }
            }
            .padding(10)
        }
        .background(VisualEffectBackground())
        .frame(width: 640, height: 420)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onAppear { isSearchFocused = true }
    }
}

private struct QuickPanelRow: View {
    let snippet: Snippet
    let isSelected: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(snippet.name)
                    if snippet.visibility != .normal {
                        Image(systemName: snippet.visibility == .encryptedHidden ? "lock.fill" : "eye.slash")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if snippet.visibility == .normal {
                    if let content = snippet.plainContent, !content.isEmpty {
                        Text(content)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    Text("●●●●● 已隐藏")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let keyword = snippet.keyword {
                Text(keyword)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(6)
        .padding(.horizontal, 6)
    }
}
