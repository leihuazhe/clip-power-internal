import SwiftUI

struct TrashView: View {
    @ObservedObject var viewModel: TrashViewModel

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.snippets.isEmpty {
                Spacer()
                Text("回收站是空的")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(viewModel.snippets) { snippet in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(snippet.name)
                            if let deletedAt = snippet.deletedAt {
                                Text("删除于 \(deletedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("恢复") { viewModel.restore(snippet) }
                        Button("永久删除", role: .destructive) { viewModel.permanentlyDelete(snippet) }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}
