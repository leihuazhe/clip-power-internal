import AppKit

enum PasteSimulator {
    /// 写入剪贴板并模拟 ⌘V。调用前浮层应已用 `.nonactivatingPanel` 关闭，
    /// 确保目标 App 仍是前台，粘贴才能落到正确的输入框里。
    /// 需要 Accessibility 授权，否则 `CGEvent.post` 不会被系统投递给其他进程。
    static func paste(_ text: String, clearAfter seconds: TimeInterval? = 20) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let changeCountAfterWrite = pasteboard.changeCount

        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        guard let seconds else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            if pasteboard.changeCount == changeCountAfterWrite {
                pasteboard.clearContents()
            }
        }
    }
}
