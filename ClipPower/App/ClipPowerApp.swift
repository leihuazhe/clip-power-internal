import SwiftUI

@main
struct ClipPowerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 管理窗口完全由 AppDelegate 里的 LibraryWindowController（AppKit）管理，
        // 这里只需要满足 App 协议要求一个 Scene，不需要 SwiftUI 自动创建/管理窗口
        // （LSUIElement App 下 WindowGroup 关闭后无法用 NSApp.windows 找回，见
        // LibraryWindowController 的注释）。
        Settings {
            EmptyView()
        }
    }
}
