import AppKit

/// 决定内容要怎么"送出去"：`.clipboard` 走系统剪贴板 + 模拟 ⌘V（普通片段，
/// 兼容性最好）；`.direct` 直接模拟键盘输入字符，完全不碰剪贴板（软隐藏/加密隐藏
/// 内容用这个，避免刚解锁的敏感内容又被剪贴板历史或别的剪贴板管理器记录下来）。
enum PasteMethod: Equatable {
    case clipboard
    case direct
}

enum PasteSimulator {
    /// 写入剪贴板并模拟 ⌘V。调用前浮层应已用 `.nonactivatingPanel` 关闭，
    /// 确保目标 App 仍是前台，粘贴才能落到正确的输入框里。
    /// 需要 Accessibility 授权，否则 `CGEvent.post` 不会被系统投递给其他进程。
    static func paste(_ text: String, clearAfter seconds: TimeInterval? = 20) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        commitPaste(clearAfter: seconds)
    }

    /// 剪贴板历史条目按类型写回剪贴板（文本/图片/文件），再模拟 ⌘V。
    static func paste(_ item: ClipboardHistoryItem, clearAfter seconds: TimeInterval? = 20) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.kind {
        case .text:
            pasteboard.setString(item.textContent ?? "", forType: .string)
        case .image:
            if let data = item.imageData, let image = NSImage(data: data) {
                pasteboard.writeObjects([image])
            }
        case .file:
            let urls = item.fileURLs.map { URL(fileURLWithPath: $0) as NSURL }
            if !urls.isEmpty {
                pasteboard.writeObjects(urls)
            }
        }

        commitPaste(clearAfter: seconds)
    }

    /// 关键词自动展开用：先模拟按 `backspaceCount` 次删除键抹掉已经打出来的触发词，
    /// 再直接输入替换内容——不经过剪贴板，一是避免污染用户当前的剪贴板内容，
    /// 二是隐藏类片段的内容不会因为展开一次就被剪贴板历史记录下来。
    /// 删除和输入之间留一点点延迟，避免系统来不及处理删除就收到后续输入。
    static func replaceTypedText(backspaceCount: Int, with content: String) {
        simulateBackspace(count: backspaceCount)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            typeDirectly(content)
        }
    }

    /// 直接模拟键盘输入整段文字，完全不经过 `NSPasteboard`——不会被我们自己的
    /// `ClipboardMonitor` 或系统里其他剪贴板管理器捕获记录，是真正的"用一次就没了"。
    /// 按小段切开发送，避免单次 `keyboardSetUnicodeString` 缓冲区过长。
    static func typeDirectly(_ text: String) {
        guard !text.isEmpty else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        let utf16Array = Array(text.utf16)
        let chunkSize = 20
        var index = 0
        while index < utf16Array.count {
            let end = min(index + chunkSize, utf16Array.count)
            let chunk = Array(utf16Array[index..<end])
            if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
               let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                keyDown.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                keyUp.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                keyDown.post(tap: .cghidEventTap)
                keyUp.post(tap: .cghidEventTap)
            }
            index = end
        }
    }

    private static func simulateBackspace(count: Int) {
        guard count > 0 else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        for _ in 0..<count {
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: true) // Delete/Backspace
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: false)
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
        }
    }

    private static func commitPaste(clearAfter seconds: TimeInterval?) {
        let pasteboard = NSPasteboard.general
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
