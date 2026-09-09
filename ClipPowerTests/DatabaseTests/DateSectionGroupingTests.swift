import XCTest
@testable import ClipPower

final class DateSectionGroupingTests: XCTestCase {
    func testTitleBucketsCorrectly() {
        let now = Date()
        let calendar = Calendar.current
        let today = now
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let earlierThisMonth = calendar.date(byAdding: .day, value: -3, to: now)!
        let lastYear = calendar.date(byAdding: .year, value: -1, to: now)!

        // 断言时也走一遍 String(localized:)，而不是硬编码中文字面量——
        // 这个函数现在会按运行环境的语言解析本地化文案，测试机的语言可能不是中文。
        XCTAssertEqual(DateSectionGrouping.title(for: today, now: now), String(localized: "今天"))
        XCTAssertEqual(DateSectionGrouping.title(for: yesterday, now: now), String(localized: "昨天"))
        // earlierThisMonth 只有在同一个日历月时才归为"本月"，跨月边界时可能落在"更早"，
        // 所以这里只断言它不是"今天"或"昨天"，避免测试在月初变得脆弱。
        XCTAssertNotEqual(DateSectionGrouping.title(for: earlierThisMonth, now: now), String(localized: "今天"))
        XCTAssertNotEqual(DateSectionGrouping.title(for: earlierThisMonth, now: now), String(localized: "昨天"))
        XCTAssertEqual(DateSectionGrouping.title(for: lastYear, now: now), String(localized: "更早"))
    }

    func testGroupedPreservesOrderAndGroupsConsecutiveItems() {
        let now = Date()
        let calendar = Calendar.current
        let today = now
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!

        let items = ["a-today", "b-today", "c-yesterday"]
        let dates: [String: Date] = ["a-today": today, "b-today": today, "c-yesterday": yesterday]

        let grouped = DateSectionGrouping.grouped(items, dateForItem: { dates[$0]! }, now: now)

        XCTAssertEqual(grouped.map(\.title), [String(localized: "今天"), String(localized: "昨天")])
        XCTAssertEqual(grouped[0].items, ["a-today", "b-today"])
        XCTAssertEqual(grouped[1].items, ["c-yesterday"])
    }
}
