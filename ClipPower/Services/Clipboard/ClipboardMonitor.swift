import AppKit
import Foundation

/// 轮询系统剪贴板的 changeCount（macOS 没有剪贴板变化的推送通知 API，
/// Raycast/Alfred 等剪贴板管理器也都是这么做的），检测到新内容就记录一条历史。
/// 按 文件 → 图片 → 文本 的优先级依次判断（Finder 复制的文件有时也会带图标的图片
/// 表示，所以必须先排除文件 URL 再判断图片）。
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

    /// 我们自己往系统剪贴板写内容时调用（比如重新粘贴剪贴板历史里的旧条目，
    /// ⌘V 必须先把内容放回剪贴板）——同步把 `lastChangeCount` 更新到最新值，
    /// 让下一次轮询不要把这次**自己造成**的变化当成"用户又复制了一次新内容"。
    ///
    /// 注意：粘贴后把该条目排到列表最前面是**想要的行为**，但那件事由
    /// `ClipboardHistoryStore.touch(id:)` 显式完成，不靠这里的监控兜。
    /// 让监控去顶有三个问题：① 依赖 0.5s 轮询，时机不确定；
    /// ② 语义上是在假装"用户复制了东西"，而用户其实是在粘贴；
    /// ③ 粘贴图片/文件时会白白把剪贴板内容重新读一遍、图片再编码一次 PNG。
    func suppressNextChange() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    private func checkPasteboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        if recordFilesIfPresent(pasteboard) { return }
        if recordImageIfPresent(pasteboard) { return }
        recordTextIfPresent(pasteboard)
    }

    private func recordFilesIfPresent(_ pasteboard: NSPasteboard) -> Bool {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
              !urls.isEmpty else {
            return false
        }

        let paths = urls.map(\.path)
        let totalSize = urls.reduce(0) { sum, url in
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil
            return sum + (size ?? 0)
        }

        try? store.record(ClipboardHistoryItem(kind: .file, fileURLs: paths, byteSize: totalSize))
        return true
    }

    private func recordImageIfPresent(_ pasteboard: NSPasteboard) -> Bool {
        guard let image = NSImage(pasteboard: pasteboard),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return false
        }

        try? store.record(ClipboardHistoryItem(
            kind: .image,
            imageData: pngData,
            imageWidth: bitmap.pixelsWide,
            imageHeight: bitmap.pixelsHigh,
            byteSize: pngData.count
        ))
        return true
    }

    private func recordTextIfPresent(_ pasteboard: NSPasteboard) {
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return }
        try? store.record(ClipboardHistoryItem(kind: .text, textContent: text))
    }
}
