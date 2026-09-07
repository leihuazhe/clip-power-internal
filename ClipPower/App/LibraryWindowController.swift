import AppKit
import SwiftUI

/// 用 AppKit 直接管理管理窗口的生命周期。
/// LSUIElement（无 Dock 图标）App 里，SwiftUI 的 WindowGroup 窗口一旦被用户关闭
/// 就不会自动重建，靠 `NSApp.windows.first` 去找窗口会找不到——所以改成自己持有
/// 一个 NSWindowController，关闭时只是隐藏（`isReleasedWhenClosed = false`），
/// 下次调用 `showWindow` 还能重新拿回同一个窗口。
final class LibraryWindowController: NSWindowController {
    convenience init(store: SnippetStore, clipboardHistoryStore: ClipboardHistoryStore) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Clip Power"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: LibraryView(store: store, clipboardHistoryStore: clipboardHistoryStore)
        )

        self.init(window: window)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
