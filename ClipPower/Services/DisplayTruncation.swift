import Foundation

/// 展示用的长度上限。
///
/// 存在的原因：SwiftUI 的 `Text` **没有惰性布局**——它会为整个字符串做完整排版，
/// 再配上 `.textSelection(.enabled)` 还要为每个字形建立选择几何。实测剪贴板历史里
/// 一条 39872 字符的内容，在浮层详情栏渲染一次要 **11.5 秒**（同一轮里其他条目都是
/// 15~40ms），表现就是方向键划到这一条时整个界面卡死。而预览区只有 ~220pt 高，
/// 肉眼最多看到几百字符，把几万字符全部排一遍纯属白烧。
enum DisplayLimit {
    /// 列表行只显示一行，而且行标题还要做换行符替换这类 O(n) 变换，
    /// 拿整条几万字符的内容来做毫无意义。
    static let rowTitle = 200

    /// 详情预览区的上限。给得比可视区域宽松很多（约 40 行），
    /// 用户往下滚一点也还有内容，同时把排版成本压到常数级。
    static let preview = 2000
}

extension String {
    /// 截断到 `limit` 个字符用于**展示**，超长时末尾加省略号。
    ///
    /// **只用于展示**——粘贴、导出、搜索、去重走的永远是完整内容。
    func truncatedForDisplay(limit: Int) -> String {
        guard count > limit else { return self }
        return String(prefix(limit)) + "…"
    }

    /// 是否被展示上限截断过（用来决定要不要在界面上提示"内容已截断"）。
    func exceedsDisplayLimit(_ limit: Int) -> Bool {
        count > limit
    }
}
