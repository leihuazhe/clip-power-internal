import Foundation

/// 列表项 + 它在扁平结果数组（`results`）里的真实下标。
///
/// 存在的意义是**不要在视图里用 `results.firstIndex(of: item)` 反查下标**：
/// 浮层左侧列表是 `LazyVStack`，行的 body 是延迟求值的——求值时机可能晚于
/// `groupedResults` 被捕获的那一帧，中间 `results` 一旦被 `reload()` 换过一轮，
/// 反查就会失败，而原来的 `?? 0` 兜底会让**多行同时算成"第 0 项"**：
/// 表现就是多行同时高亮，并且点击/回车粘贴的永远是列表第一项而不是看起来选中的那行。
/// 把下标和元素在同一次快照里绑在一起，这一类不一致就不可能发生。
struct IndexedRow<Element: Identifiable>: Identifiable {
    let index: Int
    let element: Element

    /// 视图身份沿用元素自己的 id（而不是下标）——这样 `ForEach` 的身份、
    /// `.id()` 标记、`ScrollViewReader` 的滚动目标三者完全一致，
    /// 列表重排时 SwiftUI 不会把行认错。
    var id: Element.ID { element.id }
}

/// 一个日期分组：标题 + 组内带下标的行。
typealias RowSection<Element: Identifiable> = (title: String, items: [IndexedRow<Element>])

extension Array where Element: Identifiable {
    /// 把数组包装成带真实下标的行，顺序不变。
    var indexedRows: [IndexedRow<Element>] {
        enumerated().map { IndexedRow(index: $0.offset, element: $0.element) }
    }
}
