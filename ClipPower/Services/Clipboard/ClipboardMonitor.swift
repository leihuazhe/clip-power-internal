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
