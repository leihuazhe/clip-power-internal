import Foundation

/// 组合根：应用级别共享的数据层依赖，供 App 入口与各 ViewModel 使用。
enum AppEnvironment {
    static let snippetStore = SnippetStore(dbQueue: DatabaseManager.shared.dbQueue)
    static let clipboardHistoryStore = ClipboardHistoryStore(dbQueue: DatabaseManager.shared.dbQueue)
    static let inputMethodBindingStore = InputMethodBindingStore(dbQueue: DatabaseManager.shared.dbQueue)
}
