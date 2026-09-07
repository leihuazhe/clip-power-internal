import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// 呼出片段搜索浮层，默认 ⌥+Space（可在设置里改成任意组合，比如 ⌘1）。
    static let toggleSnippetsPanel = Self("toggleSnippetsPanel", default: .init(.space, modifiers: [.option]))
    /// 呼出剪贴板历史浮层，默认 ⌘⇧V。
    static let toggleClipboardHistoryPanel = Self("toggleClipboardHistoryPanel", default: .init(.v, modifiers: [.command, .shift]))
}

/// 封装 KeyboardShortcuts 包（内部基于 Carbon HotKey API），注册全局热键。
@MainActor
final class GlobalHotkeyManager {
    static let shared = GlobalHotkeyManager()

    func register(_ name: KeyboardShortcuts.Name, action: @escaping () -> Void) {
        KeyboardShortcuts.onKeyUp(for: name, action: action)
    }
}
