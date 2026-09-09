import Foundation

/// 把一组按时间排序的元素按「今天/昨天/本月/更早」分组，用于浮层列表里
/// 对标 Raycast 的时间分区展示。假设传入元素已经按时间倒序排好，分组只是
/// 在原有顺序上打标签，不会重新排序。
enum DateSectionGrouping {
    /// 分桶器：把每次分组都要用的东西**预先算一次**，而不是按项各算一次。
    ///
    /// `Calendar.current` 和 `String(localized:)` 都不便宜——后者每次都要去
    /// bundle 里查一遍本地化表。国际化之前这四个标题是静态字面量（零成本），
    /// 改成本地化查表后，在 192 条的列表里按项各调一次就成了可感知的卡顿来源
    /// （浮层里连按方向键会明显掉帧）。整批分组只构造一个 `Bucketer` 就够了。
    private struct Bucketer {
        let calendar = Calendar.current
        let today = String(localized: "今天")
        let yesterday = String(localized: "昨天")
        let thisMonth = String(localized: "本月")
        let earlier = String(localized: "更早")

        func title(for date: Date, now: Date) -> String {
            if calendar.isDateInToday(date) { return today }
            if calendar.isDateInYesterday(date) { return yesterday }
            if calendar.isDate(date, equalTo: now, toGranularity: .month) { return thisMonth }
            return earlier
        }
    }

    static func title(for date: Date, now: Date = Date()) -> String {
        Bucketer().title(for: date, now: now)
    }

    static func grouped<T>(
        _ items: [T],
        dateForItem: (T) -> Date,
        now: Date = Date()
    ) -> [(title: String, items: [T])] {
        let bucketer = Bucketer()
        var order: [String] = []
        var buckets: [String: [T]] = [:]
        for item in items {
            let sectionTitle = bucketer.title(for: dateForItem(item), now: now)
            if buckets[sectionTitle] == nil {
                buckets[sectionTitle] = []
                order.append(sectionTitle)
            }
            buckets[sectionTitle]?.append(item)
        }
        return order.map { (title: $0, items: buckets[$0] ?? []) }
    }
}
