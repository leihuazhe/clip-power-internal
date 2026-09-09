import XCTest
@testable import ClipPower

/// 回归测试：展示用的长度截断。
///
/// 背景：浮层详情栏原来把整条内容塞进 `Text` + `.textSelection(.enabled)`，
/// 而 SwiftUI 的 `Text` 没有惰性布局。实测一条 39872 字符的剪贴板内容渲染一次要
/// 11.5 秒（同一轮其他条目 15~40ms），方向键划到这条就整个界面卡死。
/// 这里守住两条不变量：展示确实被截断了，且**完整内容没有被破坏**（粘贴要用完整的）。
final class DisplayTruncationTests: XCTestCase {
    func testShortStringIsNotTruncated() {
        let short = "hello"
        XCTAssertEqual(short.truncatedForDisplay(limit: 100), "hello")
        XCTAssertFalse(short.exceedsDisplayLimit(100))
    }

    func testAtLimitIsNotTruncated() {
        let exact = String(repeating: "a", count: 100)
        XCTAssertEqual(exact.truncatedForDisplay(limit: 100), exact, "刚好到上限不应该加省略号")
        XCTAssertFalse(exact.exceedsDisplayLimit(100))
    }

    func testOverLimitIsTruncatedWithEllipsis() {
        let long = String(repeating: "a", count: 39_872) // 实测卡死那条的长度
        let shown = long.truncatedForDisplay(limit: DisplayLimit.preview)

        XCTAssertEqual(shown.count, DisplayLimit.preview + 1, "截断到上限 + 一个省略号")
        XCTAssertTrue(shown.hasSuffix("…"))
        XCTAssertTrue(long.exceedsDisplayLimit(DisplayLimit.preview))
        XCTAssertEqual(long.count, 39_872, "原字符串不能被改动——粘贴要用完整内容")
    }

    func testClipboardRowTitleIsCappedButContentIsIntact() {
        let long = String(repeating: "x", count: 39_872)
        let item = ClipboardHistoryItem(kind: .text, textContent: long)

        // 行标题只显示一行，必须是截断过的（调用方还要对它做 O(n) 的换行符替换）。
        XCTAssertLessThanOrEqual(item.displayTitle.count, DisplayLimit.rowTitle + 1)
        // 但条目本身存的内容必须完好无损。
        XCTAssertEqual(item.textContent?.count, 39_872)
    }

    func testTruncationPreservesLeadingContentSoPreviewIsStillUseful() {
        let long = "BEGIN-MARKER" + String(repeating: "y", count: 39_872)
        let shown = long.truncatedForDisplay(limit: DisplayLimit.preview)
        XCTAssertTrue(shown.hasPrefix("BEGIN-MARKER"), "截断要保留开头，预览才有意义")
    }
}
