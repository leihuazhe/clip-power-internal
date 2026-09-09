import AppKit
import Foundation

/// 全局关键词自动展开：在任意 App 的输入框里打出一个片段的触发词，立刻替换成对应内容
/// （对标 Espanso/TextExpander，也是 Raycast 没有但用户想要的能力）。
///
/// 实现方式：`NSEvent.addGlobalMonitorForEvents` 只读监听全局按键（不拦截、不消费，
/// 用户正常输入完全不受影响），维护一个滚动缓冲区，每敲一个字符就检查缓冲区末尾是否
/// 命中某个触发词；命中后用 `PasteSimulator` 模拟退格删掉刚打的触发词、再粘贴替换内容。
///
/// 加密隐藏的片段不参与——那需要 Touch ID，不适合在打字时无感触发。
/// 已知局限（和大多数简单文本替换工具一样）：如果触发词恰好是另一个更长单词的后缀
/// （比如触发词是 "gitc"，用户打的是 "logitc"），也会被命中展开，需要用户自己挑
/// 不容易和普通单词撞在一起的触发词。
@MainActor
final class TextExpansionMonitor {
    private let store: SnippetStore
    private let keywordIndex: KeywordIndex
    private var globalMonitor: Any?
    private var buffer = ""
    private let maxBufferLength = 40

    init(store: SnippetStore, keywordIndex: KeywordIndex) {
        self.store = store
        self.keywordIndex = keywordIndex
    }

    func start() {
        stop()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }

    private func handle(_ event: NSEvent) {
        // 带 ⌘/⌃/⌥ 的组合键（复制/粘贴/切换 App 等）不参与拼词，直接清空缓冲区，
        // 避免把不相关的按键片段误判成触发词的一部分。
        let relevantModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        if !event.modifierFlags.intersection(relevantModifiers).isEmpty {
            buffer = ""
            return
        }

        switch event.keyCode {
        case 51: // Delete/Backspace：跟着删掉缓冲区最后一个字符，保持和输入框内容一致
            if !buffer.isEmpty {
                buffer.removeLast()
            }
            return
        case 36, 76, 48, 123, 124, 125, 126: // Return/小键盘Enter/Tab/方向键：认为一个"词"结束了
            buffer = ""
            return
        default:
            break
        }

        guard let characters = event.charactersIgnoringModifiers, !characters.isEmpty else { return }
        buffer.append(characters)
        if buffer.count > maxBufferLength {
            buffer.removeFirst(buffer.count - maxBufferLength)
        }

        checkForMatch()
    }

    private func checkForMatch() {
        guard let keyword = keywordIndex.matchSuffix(of: buffer),
              let snippetID = keywordIndex.snippetID(forKeyword: keyword) else {
            return
        }

        // 立刻清空缓冲区，避免同一次输入被重复展开。
        buffer = ""
        expand(snippetID: snippetID, keywordLength: keyword.count)
    }

    private func expand(snippetID: String, keywordLength: Int) {
        guard let snippet = try? store.fetchByID(snippetID),
              snippet.visibility != .encryptedHidden,
              let content = snippet.plainContent else {
            return
        }
        PasteSimulator.replaceTypedText(backspaceCount: keywordLength, with: content)
        try? store.recordUsage(id: snippet.id)
    }
}
