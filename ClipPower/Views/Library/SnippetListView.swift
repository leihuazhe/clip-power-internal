import SwiftUI

struct SnippetListView: View {
    let snippets: [Snippet]
    @Binding var selection: String?
    @Binding var searchText: String

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索片段...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)

            Divider()

            if snippets.isEmpty {
                Spacer()
                Text(searchText.isEmpty ? "还没有片段，点击右上角「+」创建一个" : "没有匹配的片段")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List(snippets, selection: $selection) { snippet in
                    SnippetRow(snippet: snippet).tag(snippet.id)
                }
                .listStyle(.inset)
            }
        }
    }
}

private struct SnippetRow: View {
    let snippet: Snippet

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(snippet.name).font(.body)
                if snippet.visibility != .normal {
                    Image(systemName: snippet.visibility == .encryptedHidden ? "lock.fill" : "eye.slash")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 6) {
                if let keyword = snippet.keyword {
                    Text(keyword)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(Capsule())
                }
                if snippet.visibility == .normal {
                    if let preview = snippet.plainContent, !preview.isEmpty {
                        Text(preview)
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
        }
        .padding(.vertical, 2)
    }
}
