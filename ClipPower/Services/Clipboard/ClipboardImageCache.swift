import AppKit

/// 剪贴板历史里图片条目的解码缓存。
///
/// `NSImage(data:)` 每次都会真的解一遍 PNG。而 SwiftUI 的行 body / 右侧详情栏
/// 在滚动、选中项变化时都会被反复求值——不缓存的话，选中一张图之后每按一次
/// 方向键都要完整重解一次，是明显的卡顿来源。
///
/// 用 `NSCache` 而不是普通字典：内存紧张时系统会自动回收，避免历史里图片多了
/// 之后把解码结果无限堆在内存里（原始 PNG 字节本来就已经在数据库/条目里了，
/// 缓存丢了只是下次重解一遍，没有正确性问题）。
@MainActor
enum ClipboardImageCache {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 60
        return cache
    }()

    static func image(for item: ClipboardHistoryItem) -> NSImage? {
        guard let data = item.imageData else { return nil }

        let key = item.id as NSString
        if let cached = cache.object(forKey: key) { return cached }

        guard let image = NSImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}
