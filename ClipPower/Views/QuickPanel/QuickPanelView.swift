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

            HStack(spacing: 0) {
                listColumn
                Divider()
                QuickPanelDetailPane(snippet: viewModel.selectedSnippet)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()
            HStack(spacing: 8) {
                PanelHintPill(text: "↩ 粘贴")
                PanelHintPill(text: "↑↓ 切换")
                Spacer()
                if viewModel.isRevealing {
                    ProgressView().controlSize(.small)
                    Text("验证中...").font(.caption2).foregroundStyle(.secondary)
                } else if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage).font(.caption2).foregroundStyle(.red)
                }
                PanelHintPill(text: "Esc 关闭")
            }
            .padding(10)
        }
        .onAppear {
            // 见 ClipboardHistoryView 里同样的注释：面板第一次显示时窗口还没真正变成
            // key window，onAppear 就跑完了，FocusState 设置不生效，延迟到下一个
            // runloop 周期再设。
            DispatchQueue.main.async {
                isSearchFocused = true
            }
        }
    }

    private var listColumn: some View {
        Group {
            if viewModel.results.isEmpty {
                VStack {
                    Spacer()
                    Text("没有匹配的片段").foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(viewModel.groupedResults, id: \.title) { group in
                                Text(group.title)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 14)
                                    .padding(.top, 10)
                                    .padding(.bottom, 4)
                                ForEach(group.items) { snippet in
                                    let index = viewModel.results.firstIndex(of: snippet) ?? 0
                                    QuickPanelRow(snippet: snippet, isSelected: index == viewModel.selectedIndex)
                                        .id(index)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            viewModel.selectRow(at: index)
                                            viewModel.confirmSelection()
                                        }
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    // 方向键移动选中项时，选中的行可能被滚出可见区域——看起来就像
                    // "高亮块消失了"，而不是真的没跟着移动。用 ScrollViewReader 让
                    // 选中项始终滚动到可见范围内。
                    .onChange(of: viewModel.selectedIndex) { newIndex in
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(width: 260)
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
                        .lineLimit(1)
                    if snippet.visibility != .normal {
                        Image(systemName: snippet.visibility == .encryptedHidden ? "lock.fill" : "eye.slash")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if let keyword = snippet.keyword {
                    Text(keyword)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(6)
        .padding(.horizontal, 6)
    }
}

/// 右侧详情栏：大字内容预览 + Information 元数据区，对标 Raycast 的 Snippets 面板。
private struct QuickPanelDetailPane: View {
    let snippet: Snippet?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let snippet {
                contentPreview(for: snippet)
                Spacer(minLength: 0)
                infoSection(for: snippet)
            } else {
                Spacer()
                HStack {
                    Spacer()
                    Text("选择一个片段查看详情").foregroundStyle(.secondary)
                    Spacer()
                }
                Spacer()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func contentPreview(for snippet: Snippet) -> some View {
        // 软隐藏/加密隐藏都不能在这里露出明文——这个预览区是方向键选中就自动刷新的，
        // 不是用户主动点击"查看"，一旦露出就等于"选中即看到"，跟隐藏的初衷相悖。
        // 隐藏内容的查看/解锁走管理窗口里那套需要主动点击的流程，浮层这里只管盲选粘贴。
        if snippet.visibility != .normal {
            VStack(spacing: 8) {
                Image(systemName: snippet.visibility == .encryptedHidden ? "lock.fill" : "eye.slash")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text(snippet.visibility == .encryptedHidden ? "内容已加密，回车粘贴时会验证身份" : "内容已隐藏，回车可直接粘贴")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
        } else {
            ScrollView {
                Text(snippet.plainContent ?? "")
                    .font(.system(size: 18))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func infoSection(for snippet: Snippet) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Information")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)
            Divider()
            InfoRow(label: "名称", value: snippet.name)
            if let keyword = snippet.keyword {
                InfoRow(label: "触发词", value: keyword)
            }
            InfoRow(label: "可见性", value: snippet.visibility.displayName)
            InfoRow(label: "使用次数", value: "\(snippet.usageCount)")
            if let lastUsedAt = snippet.lastUsedAt {
                InfoRow(label: "最近使用", value: lastUsedAt.formatted(date: .abbreviated, time: .shortened))
            }
            InfoRow(label: "创建于", value: snippet.createdAt.formatted(date: .abbreviated, time: .shortened))
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(label).foregroundStyle(.secondary)
                Spacer()
                Text(value)
            }
            .font(.caption)
            .padding(.vertical, 6)
            Divider()
        }
    }
}

struct PanelHintPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.12))
            .clipShape(Capsule())
            .foregroundStyle(.secondary)
    }
}
