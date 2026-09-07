import Foundation
import Combine

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published private(set) var snippets: [Snippet] = []
    @Published var searchText: String = "" {
        didSet { reload() }
    }
    @Published var errorMessage: String?

    private let store: SnippetStore
    private let encryptionService: SnippetEncryptionService

    init(store: SnippetStore, encryptionService: SnippetEncryptionService = SnippetEncryptionService()) {
        self.store = store
        self.encryptionService = encryptionService
        reload()
    }

    func reload() {
        do {
            snippets = try store.search(searchText)
        } catch {
            errorMessage = "加载片段失败：\(error.localizedDescription)"
        }
    }

    /// 创建或更新一个片段。支持三态可见性切换：
    /// 切到「加密隐藏」会先触发一次 Touch ID / 密码鉴权再加密；
    /// 从「加密隐藏」切回公开/软隐藏会先解密还原明文再应用新内容。
    @discardableResult
    func save(draft: SnippetDraft, existing: Snippet?) async -> Bool {
        do {
            var snippet = existing ?? Snippet(name: draft.name)
            snippet.name = draft.name
            snippet.keyword = draft.keyword
            snippet.tags = draft.tags

            switch draft.visibility {
            case .encryptedHidden:
                snippet.plainContent = draft.content
                snippet.cipherContent = nil
                snippet = try await encryptionService.hide(snippet)
            case .normal, .softHidden:
                if snippet.visibility == .encryptedHidden {
                    snippet = try await encryptionService.unhide(snippet)
                }
                snippet.plainContent = draft.content
                snippet.cipherContent = nil
                snippet.keyID = nil
                snippet.visibility = draft.visibility
            }

            if existing != nil {
                _ = try store.update(snippet)
            } else {
                _ = try store.create(snippet)
            }
            reload()
            return true
        } catch SnippetStoreError.duplicateKeyword {
            errorMessage = "触发词「\(draft.keyword ?? "")」已被占用，请换一个"
            return false
        } catch {
            errorMessage = "保存失败：\(error.localizedDescription)"
            return false
        }
    }

    func softDelete(_ snippet: Snippet) {
        do {
            try store.softDelete(id: snippet.id)
            reload()
        } catch {
            errorMessage = "删除失败：\(error.localizedDescription)"
        }
    }

    /// 查看隐藏内容：软隐藏直接返回明文，加密隐藏会触发一次 Touch ID / 密码鉴权。
    func reveal(_ snippet: Snippet) async -> String? {
        guard snippet.visibility == .encryptedHidden else {
            return snippet.plainContent
        }
        do {
            return try await encryptionService.reveal(snippet)
        } catch {
            errorMessage = "验证失败：\(error.localizedDescription)"
            return nil
        }
    }

    /// 取消软隐藏：不涉及加解密，直接把可见性改回公开。
    func unhideSoft(_ snippet: Snippet) {
        var updated = snippet
        updated.visibility = .normal
        persist(updated)
    }

    /// 解除加密隐藏：先解密还原明文，再把可见性改回公开。
    func unhideEncrypted(_ snippet: Snippet) async {
        do {
            let restored = try await encryptionService.unhide(snippet)
            persist(restored)
        } catch {
            errorMessage = "解除加密隐藏失败：\(error.localizedDescription)"
        }
    }

    private func persist(_ snippet: Snippet) {
        do {
            _ = try store.update(snippet)
            reload()
        } catch {
            errorMessage = "更新失败：\(error.localizedDescription)"
        }
    }
}
