import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// ClipPower 的通用打开快捷键，默认 ⌥+Space；打开合并面板并默认定位到「片段」Tab。
    static let toggleClipPowerPanel = Self("toggleClipPowerPanel", default: .init(.space, modifiers: [.option]))
    /// 直接打开合并面板并定位到「片段」Tab，默认不绑定，用户可在设置里自定义（比如 ⌘1）。
    static let toggleSnippetsPanel = Self("toggleSnippetsPanel")
    /// 直接打开合并面板并定位到「剪贴板历史」Tab，默认 ⌘⇧V。
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
