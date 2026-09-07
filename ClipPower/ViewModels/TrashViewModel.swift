import Foundation
import Combine

@MainActor
final class TrashViewModel: ObservableObject {
    @Published private(set) var snippets: [Snippet] = []
    @Published var errorMessage: String?

    private let store: SnippetStore
    private let onChange: () -> Void

    init(store: SnippetStore, onChange: @escaping () -> Void = {}) {
        self.store = store
        self.onChange = onChange
        reload()
    }

    func reload() {
        do {
            snippets = try store.fetchTrash()
        } catch {
            errorMessage = "加载回收站失败：\(error.localizedDescription)"
        }
    }

    func restore(_ snippet: Snippet) {
        do {
            try store.restore(id: snippet.id)
            reload()
            onChange()
        } catch {
            errorMessage = "恢复失败：\(error.localizedDescription)"
        }
    }

    func permanentlyDelete(_ snippet: Snippet) {
        do {
            try store.permanentlyDelete(id: snippet.id)
            reload()
        } catch {
            errorMessage = "永久删除失败：\(error.localizedDescription)"
        }
    }
}
