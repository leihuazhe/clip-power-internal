import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// ClipPower 的通用打开快捷键，默认 ⌥+Space；打开合并面板并默认定位到「片段」Tab。
    static let toggleClipPowerPanel = Self("toggleClipPowerPanel", default: .init(.space, modifiers: [.option]))
    /// 直接打开合并面板并定位到「片段」Tab，默认不绑定，用户可在设置里自定义（比如 ⌘1）。
    static let toggleSnippetsPanel = Self("toggleSnippetsPanel")
    /// 直接打开合并面板并定位到「剪贴板历史」Tab，默认 ⌘⇧V。
    static let toggleClipboardHistoryPanel = Self("toggleClipboardHistoryPanel", default: .init(.v, modifiers: [.command, .shift]))
    /// 把前台窗口在按物理位置排好序的屏幕环形列表里往后/往前挪一格；全屏窗口会退出全屏再
    /// 重新全屏到目标屏幕，非全屏窗口直接原样搬过去。
    /// 默认 ⌃⌥+方向键——单独 ⌃+方向键被系统占用（切全屏 Space/Mission Control），加 ⌥ 避开；
    /// 跟 Rectangle 默认的窗口分屏快捷键用的是同一个组合，装了 Rectangle 的话可能要在设置里改一下。
    static let moveFrontmostWindowToNextScreen = Self("moveFrontmostWindowToNextScreen", default: .init(.rightArrow, modifiers: [.control, .option]))
    static let moveFrontmostWindowToPreviousScreen = Self("moveFrontmostWindowToPreviousScreen", default: .init(.leftArrow, modifiers: [.control, .option]))
}

/// 封装 KeyboardShortcuts 包（内部基于 Carbon HotKey API），注册全局热键。
@MainActor
final class GlobalHotkeyManager {
    static let shared = GlobalHotkeyManager()

    func register(_ name: KeyboardShortcuts.Name, action: @escaping () -> Void) {
        KeyboardShortcuts.onKeyUp(for: name, action: action)
    }
}
