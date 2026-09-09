import Foundation

/// 维护「触发词 -> 片段 id」的内存索引，供全局关键词自动展开使用。
/// 加密隐藏的片段不参与自动展开——那需要 Touch ID，不适合在用户打字时无感触发。
/// 监听 `.snippetsDidChange` 通知自动刷新，不需要外部手动调用 reload（除了初始化）。
@MainActor
final class KeywordIndex {
    private let store: SnippetStore
    private var keywordToSnippetID: [String: String] = [:]
    private var maxKeywordLength = 0
    private var observer: NSObjectProtocol?

    init(store: SnippetStore) {
        self.store = store
        reload()
        observer = NotificationCenter.default.addObserver(
            forName: .snippetsDidChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.reload()
        }
    }

    func reload() {
        let all = (try? store.fetchActive()) ?? []
        var index: [String: String] = [:]
        var longest = 0
        for snippet in all where snippet.visibility != .encryptedHidden {
            guard let keyword = snippet.keyword, !keyword.isEmpty else { continue }
            index[keyword] = snippet.id
            longest = max(longest, keyword.count)
        }
        keywordToSnippetID = index
        maxKeywordLength = longest
    }

    /// 返回缓冲区末尾能匹配到的最长触发词（如果有的话），优先匹配更长的（比如
    /// 同时存在 "pwd" 和 "pwdd" 两个触发词时，输入 "pwdd" 应该匹配 "pwdd" 而不是 "pwd"）。
    func matchSuffix(of buffer: String) -> String? {
        guard !buffer.isEmpty, maxKeywordLength > 0 else { return nil }
        let characters = Array(buffer)
        let upperBound = min(characters.count, maxKeywordLength)
        for length in stride(from: upperBound, through: 1, by: -1) {
            let candidate = String(characters.suffix(length))
            if keywordToSnippetID[candidate] != nil {
                return candidate
            }
        }
        return nil
    }

    func snippetID(forKeyword keyword: String) -> String? {
        keywordToSnippetID[keyword]
    }
}
