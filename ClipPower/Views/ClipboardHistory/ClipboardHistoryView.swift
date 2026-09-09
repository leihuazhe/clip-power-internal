import SwiftUI
import AppKit

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

            HStack(spacing: 0) {
                listColumn
                Divider()
                ClipboardDetailPane(item: viewModel.selectedItem)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()
            HStack(spacing: 8) {
                PanelHintPill(text: "↩ 粘贴")
                PanelHintPill(text: "↑↓ 切换")
                Spacer()
                PanelHintPill(text: "Esc 关闭")
            }
            .padding(10)
        }
        .onAppear {
            // 面板第一次显示时，makeKeyAndOrderFront 还没真正让窗口变成 key window，
            // onAppear 就已经跑完了——这时设置 FocusState 不会生效（回车摸不到
            // onSubmit，方向键还能用是因为那是在窗口级别监听的）。延迟到下一个
            // runloop 周期再设，等窗口真正拿到键盘焦点。第二次之后窗口已经"热"了，
            // 没有这个问题，但延迟设置无副作用，就不用分场景处理了。
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
                    Text("剪贴板历史是空的").foregroundStyle(.secondary)
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
                                ForEach(group.items) { item in
                                    let index = viewModel.results.firstIndex(of: item) ?? 0
                                    ClipboardHistoryRow(item: item, isSelected: index == viewModel.selectedIndex)
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
                    // 见 QuickPanelView 里同样的注释：没有这个的话，选中项被方向键移出
                    // 可见区域时，看起来就像高亮块直接消失了。
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

private struct ClipboardHistoryRow: View {
    let item: ClipboardHistoryItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            thumbnail
            Text(item.displayTitle.replacingOccurrences(of: "\n", with: " ⏎ "))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(6)
        .padding(.horizontal, 6)
    }

    @ViewBuilder
    private var thumbnail: some View {
        switch item.kind {
        case .text:
            Image(systemName: "doc.plaintext").foregroundStyle(.secondary)
        case .image:
            if let data = item.imageData, let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        case .file:
            Image(systemName: "doc").foregroundStyle(.secondary)
        }
    }
}

/// 右侧详情栏：内容预览（文本/图片/文件）+ Information 元数据区，
/// 对标 Raycast 的 Clipboard History 面板。
private struct ClipboardDetailPane: View {
    let item: ClipboardHistoryItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let item {
                contentPreview(for: item)
                Spacer(minLength: 0)
                infoSection(for: item)
            } else {
                Spacer()
                HStack {
                    Spacer()
                    Text("选择一项查看详情").foregroundStyle(.secondary)
                    Spacer()
                }
                Spacer()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func contentPreview(for item: ClipboardHistoryItem) -> some View {
        switch item.kind {
        case .text:
            ScrollView {
                Text(item.textContent ?? "")
                    .font(.system(size: 18))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .image:
            if let data = item.imageData, let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 220)
            } else {
                Text("图片数据不可用").foregroundStyle(.secondary)
            }
        case .file:
            VStack(alignment: .leading, spacing: 4) {
                ForEach(item.fileURLs, id: \.self) { path in
                    Text(URL(fileURLWithPath: path).lastPathComponent)
                        .font(.system(size: 16))
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func infoSection(for item: ClipboardHistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Information")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)
            Divider()
            InfoRow(label: "类型", value: typeLabel(for: item.kind))
            switch item.kind {
            case .text:
                InfoRow(label: "字符数", value: "\(item.textContent?.count ?? 0)")
            case .image:
                if let w = item.imageWidth, let h = item.imageHeight {
                    InfoRow(label: "尺寸", value: "\(w)×\(h)")
                }
                InfoRow(label: "大小", value: formattedByteSize(item.byteSize))
            case .file:
                InfoRow(label: "数量", value: localizedFormat("itemCountFormat", item.fileURLs.count))
                InfoRow(label: "大小", value: formattedByteSize(item.byteSize))
            }
            InfoRow(label: "记录于", value: item.createdAt.formatted(date: .abbreviated, time: .shortened))
        }
    }

    private func typeLabel(for kind: ClipboardContentKind) -> String {
        switch kind {
        case .text: return "文本"
        case .image: return "图片"
        case .file: return "文件"
        }
    }

    private func formattedByteSize(_ bytes: Int?) -> String {
        guard let bytes else { return "-" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
