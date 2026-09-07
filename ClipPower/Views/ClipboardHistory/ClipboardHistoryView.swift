import SwiftUI

struct ClipboardHistoryView: View {
    @ObservedObject var viewModel: ClipboardHistoryViewModel
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "doc.on.clipboard").foregroundStyle(.secondary)
                TextField("搜索剪贴板历史...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($isSearchFocused)
                    .onSubmit { viewModel.confirmSelection() }
                if !viewModel.results.isEmpty {
                    Button("清空") { viewModel.clearAll() }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)

            Divider()

            if viewModel.results.isEmpty {
                Spacer()
                Text("剪贴板历史是空的")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(viewModel.results.enumerated()), id: \.element.id) { index, item in
                            ClipboardHistoryRow(item: item, isSelected: index == viewModel.selectedIndex)
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
                Text("↩ 粘贴").font(.caption2).foregroundStyle(.secondary)
                Text("↑↓ 切换").font(.caption2).foregroundStyle(.secondary)
                Text("Esc 关闭").font(.caption2).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(10)
        }
        .background(VisualEffectBackground())
        .frame(width: 640, height: 420)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onAppear { isSearchFocused = true }
    }
}

private struct ClipboardHistoryRow: View {
    let item: ClipboardHistoryItem
    let isSelected: Bool

    var body: some View {
        HStack {
            Text(item.content.replacingOccurrences(of: "\n", with: " ⏎ "))
                .lineLimit(1)
            Spacer()
            Text(item.createdAt.formatted(date: .omitted, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(6)
        .padding(.horizontal, 6)
    }
}
