import AppKit
import Foundation

/// 轮询系统剪贴板的 changeCount（macOS 没有剪贴板变化的推送通知 API，
/// Raycast/Alfred 等剪贴板管理器也都是这么做的），检测到新内容就记录一条历史。
@MainActor
final class ClipboardMonitor {
    private let store: ClipboardHistoryStore
    private var timer: Timer?
    private var lastChangeCount: Int

    init(store: ClipboardHistoryStore) {
        self.store = store
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    func start(interval: TimeInterval = 0.5) {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkPasteboard()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func checkPasteboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        guard let text = pasteboard.string(forType: .string) else { return }
        try? store.record(text)
    }
}
