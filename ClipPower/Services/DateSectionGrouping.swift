import Foundation

/// 把一组按时间排序的元素按「今天/昨天/本月/更早」分组，用于浮层列表里
/// 对标 Raycast 的时间分区展示。假设传入元素已经按时间倒序排好，分组只是
/// 在原有顺序上打标签，不会重新排序。
enum DateSectionGrouping {
    static func title(for date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return String(localized: "今天") }
        if calendar.isDateInYesterday(date) { return String(localized: "昨天") }
        if calendar.isDate(date, equalTo: now, toGranularity: .month) { return String(localized: "本月") }
        return String(localized: "更早")
    }

    static func grouped<T>(
        _ items: [T],
        dateForItem: (T) -> Date,
        now: Date = Date()
    ) -> [(title: String, items: [T])] {
        var order: [String] = []
        var buckets: [String: [T]] = [:]
        for item in items {
            let sectionTitle = title(for: dateForItem(item), now: now)
            if buckets[sectionTitle] == nil {
                buckets[sectionTitle] = []
                order.append(sectionTitle)
            }
            buckets[sectionTitle]?.append(item)
        }
        return order.map { (title: $0, items: buckets[$0] ?? []) }
    }
}
