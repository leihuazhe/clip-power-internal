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

    private var keyMonitor: Any?

    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .borderless],
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
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
        delegate = self

        self.contentView = contentView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func windowDidResignKey(_ notification: Notification) {
        onEscape?()
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
            guard let self, self.isVisible else { return event }
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
