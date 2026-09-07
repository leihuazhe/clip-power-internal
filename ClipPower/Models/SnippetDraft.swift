import Foundation

/// 编辑器表单产出的草稿，交给 ViewModel 决定如何持久化（含是否需要加解密）。
struct SnippetDraft {
    var name: String
    var keyword: String?
    var content: String
    var tags: [String]
    var visibility: SnippetVisibility
}
