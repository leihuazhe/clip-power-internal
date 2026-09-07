import SwiftUI

struct SnippetDetailView: View {
    let snippet: Snippet
    @ObservedObject var libraryViewModel: LibraryViewModel
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var revealedText: String?
    @State private var isRevealing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if !snippet.tags.isEmpty {
                HStack {
                    ForEach(snippet.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
            }

            Divider()

            contentArea

            Spacer()

            Text("更新于 \(snippet.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .onChange(of: snippet.id) { _ in
            revealedText = nil
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(snippet.name).font(.title2.bold())
                    visibilityBadge
                }
                if let keyword = snippet.keyword {
                    Text("触发词：\(keyword)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if snippet.visibility != .encryptedHidden || revealedText != nil {
                Button("编辑", action: onEdit)
            }
            Button("删除", role: .destructive, action: onDelete)
        }
    }

    @ViewBuilder
    private var visibilityBadge: some View {
        switch snippet.visibility {
        case .normal:
            EmptyView()
        case .softHidden:
            Label("软隐藏", systemImage: "eye.slash")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .encryptedHidden:
            Label("加密隐藏", systemImage: "lock.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var contentArea: some View {
        switch snippet.visibility {
        case .normal:
            plainTextView(snippet.plainContent ?? "")

        case .softHidden:
            if let revealedText {
                VStack(alignment: .leading, spacing: 12) {
                    plainTextView(revealedText)
                    HStack {
                        Button("重新隐藏") { self.revealedText = nil }
                        Button("取消软隐藏") { libraryViewModel.unhideSoft(snippet) }
                    }
                }
            } else {
                maskedPlaceholder(icon: "eye.slash", text: "内容已隐藏，点击查看") {
                    revealedText = snippet.plainContent
                }
            }

        case .encryptedHidden:
            if let revealedText {
                VStack(alignment: .leading, spacing: 12) {
                    plainTextView(revealedText)
                    HStack {
                        Button("重新隐藏") { self.revealedText = nil }
                        Button("解除加密隐藏") {
                            Task { await libraryViewModel.unhideEncrypted(snippet) }
                        }
                    }
                }
            } else {
                maskedPlaceholder(icon: "lock.fill", text: "内容已加密，需要验证身份后才能查看", isBusy: isRevealing) {
                    reveal()
                }
            }
        }
    }

    private func plainTextView(_ text: String) -> some View {
        ScrollView {
            Text(text)
                .font(.body.monospaced())
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    private func maskedPlaceholder(icon: String, text: String, isBusy: Bool = false, action: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(text).foregroundStyle(.secondary)
            Button(action: action) {
                if isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Text("点击查看")
                }
            }
            .disabled(isBusy)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func reveal() {
        isRevealing = true
        Task {
            revealedText = await libraryViewModel.reveal(snippet)
            isRevealing = false
        }
    }
}
