import Foundation
import GRDB
import KeyboardShortcuts

/// 一条"输入源 → 全局快捷键"绑定。`id` 是绑定自身的 UUID，不是 `inputSourceID`——
/// `inputSourceID`（如 `com.apple.inputmethod.SCIM.ITABC`）含有 `.`，不能直接拿去拼
/// `KeyboardShortcuts.Name`（该包规定 raw string 不能含 `.`），所以快捷键 key 用 `id`。
struct InputMethodBinding: Identifiable, Codable, Sendable, Equatable {
    var id: String
    var inputSourceID: String
    var displayName: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        inputSourceID: String,
        displayName: String,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.inputSourceID = inputSourceID
        self.displayName = displayName
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var shortcutName: KeyboardShortcuts.Name {
        KeyboardShortcuts.Name("inputMethodHotkey_\(id)")
    }
}

extension InputMethodBinding: FetchableRecord, PersistableRecord {
    static let databaseTableName = "inputMethodBinding"
}
