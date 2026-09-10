import AppKit

/// 全局呼出的浮层面板基类，对标 Raycast 的交互：
/// `.nonactivatingPanel` 使其不会抢占前台激活状态，原本聚焦的输入框不会失焦，
/// 关闭浮层后原 App 天然恢复焦点，模拟粘贴才能落到正确的位置。
/// 失去焦点（点了别的 App / 别的窗口）或按 Esc 都会关闭浮层。
/// Snippets 面板和剪贴板历史面板共用这一套窗口行为，各自只需要提供内容视图
/// 和上下键的处理逻辑。
class FloatingPanel: NSPanel, NSWindowDelegate {
    var onMoveDown: (() -> Void)?
    var onMoveUp: (() -> Void)?
    var onEscape: (() -> Void)?
    var onTabKey: (() -> Void)?
    var onReturn: (() -> Void)?
    /// 窗口真正拿到键盘焦点时触发（而不是 `present()` 调用完那一刻，也不是 SwiftUI
    /// `onAppear` 的下一个 runloop——这两个都只是"大概率已经 key 了"的猜测，`.nonactivatingPanel`
    /// 不激活整个 App，窗口服务器把 key 状态真正批给这个窗口有额外的、不确定的延迟。
    /// 有时候（尤其是从别的 App/别的 Space 呼出）这个延迟会跨过那个猜测的时间点，
    /// SwiftUI 那边设 `FocusState` 时窗口其实还没 key，设置被静默丢弃，
    /// 输入框始终没拿到第一响应者——之后打字进不了框，只会撞上系统提示音。
    /// 这里才是"窗口已经 key 了"唯一确定为真的时刻，用它来兜底重新聚焦。
    var onBecomeKey: (() -> Void)?

    private var keyMonitor: Any?

    init(contentView: NSView) {
        // 不要 `.titled`——即使隐藏了标题文字、设了透明标题栏，styleMask 里带 `.titled`
        // 仍然会在窗口顶部保留一条方形的系统标题栏区域，盖在 SwiftUI 的圆角裁剪之上，
        // 导致左右分栏面板的上边两个角看起来是方的。纯 `.borderless` 才能让四个角
        // 都跟着内容视图的圆角走。
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        delegate = self

        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 20
        contentView.layer?.masksToBounds = true
        self.contentView = contentView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func windowDidResignKey(_ notification: Notification) {
        onEscape?()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        onBecomeKey?()
    }

    func centerOnActiveScreen() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - frame.width / 2
        let y = screenFrame.midY - frame.height / 2 + screenFrame.height * 0.12
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    func present() {
        centerOnActiveScreen()
        installKeyMonitorIfNeeded()
        makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        guard isVisible else { return }
        orderOut(nil)
        removeKeyMonitor()
    }

    private func installKeyMonitorIfNeeded() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // 必须判 `isKeyWindow` 而不是 `isVisible`：这是个 App 级的本地监听器，
            // 只要浮层还开着就会拦截本 App **所有**窗口的按键——如果只判可见性，
            // 浮层开着的同时用户在管理窗口里操作，管理窗口的方向键/回车/Esc 会被
            // 这里悄悄吃掉（比如新建片段表单里按 Esc 关不掉）。
            guard let self, self.isKeyWindow else { return event }
            switch event.keyCode {
            case 125: // ↓
                self.onMoveDown?()
                return nil
            case 126: // ↑
                self.onMoveUp?()
                return nil
            case 53: // Esc
                self.onEscape?()
                return nil
            case 48: // Tab
                self.onTabKey?()
                return nil
            case 36, 76: // Return / 小键盘 Enter
                // 回车也在窗口级别处理，不再依赖搜索框的 `.onSubmit`。
                // 之前两次"选好内容按回车没反应"的 bug 都是同一个根因：
                // `.onSubmit` 要求搜索框真正拿到键盘第一响应者，而这在浮层
                // 首次呼出等时序下并不保证；方向键一直正常恰恰是因为它走的是
                // 这个窗口级监听。放到这里之后，回车和方向键的可靠性彻底一致。
                // 事件被吃掉（返回 nil），所以不会和 `.onSubmit` 重复触发。
                self.onReturn?()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}
