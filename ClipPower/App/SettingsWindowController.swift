import AppKit
import SwiftUI

/// 和 LibraryWindowController 同样的道理：AppKit 自己管理窗口生命周期，
/// 关闭时只隐藏不销毁，避免 LSUIElement App 下 SwiftUI 窗口关闭后找不回来的问题。
final class SettingsWindowController: NSWindowController {
    private var viewModel: SettingsViewModel!

    convenience init(clipboardHistoryStore: ClipboardHistoryStore) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 300),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "设置"
        window.center()
        window.isReleasedWhenClosed = false

        self.init(window: window)

        let viewModel = SettingsViewModel(clipboardStore: clipboardHistoryStore)
        self.viewModel = viewModel
        window.contentView = NSHostingView(rootView: SettingsView(viewModel: viewModel))
    }

    func show() {
        viewModel?.reload()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
