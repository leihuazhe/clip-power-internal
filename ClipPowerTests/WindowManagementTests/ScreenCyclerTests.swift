import XCTest
@testable import ClipPower

final class ScreenCyclerTests: XCTestCase {
    func test_nextScreenFrame_singleScreen_returnsNil() {
        let only = CGRect(x: 0, y: 0, width: 1440, height: 900)
        XCTAssertNil(ScreenCycler.nextScreenFrame(currentFrame: only, screenFrames: [only]))
    }

    func test_nextScreenFrame_twoScreens_wrapsBackAndForth() {
        let left = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let right = CGRect(x: 1440, y: 0, width: 1920, height: 1080)

        XCTAssertEqual(ScreenCycler.nextScreenFrame(currentFrame: left, screenFrames: [left, right]), right)
        XCTAssertEqual(ScreenCycler.nextScreenFrame(currentFrame: right, screenFrames: [left, right]), left)
    }

    func test_nextScreenFrame_threeScreens_ordersByXRegardlessOfInputOrder() {
        let left = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let middle = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let right = CGRect(x: 1440, y: 0, width: 2560, height: 1440)
        // 输入顺序打乱，验证内部按 x 坐标重新排序而不是依赖入参顺序。
        let shuffled = [right, left, middle]

        XCTAssertEqual(ScreenCycler.nextScreenFrame(currentFrame: left, screenFrames: shuffled), middle)
        XCTAssertEqual(ScreenCycler.nextScreenFrame(currentFrame: middle, screenFrames: shuffled), right)
        XCTAssertEqual(ScreenCycler.nextScreenFrame(currentFrame: right, screenFrames: shuffled), left)
    }

    func test_nextScreenFrame_currentFrameNotInList_fallsBackToLeftmost() {
        let left = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let right = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let unknown = CGRect(x: 9999, y: 9999, width: 100, height: 100)

        XCTAssertEqual(ScreenCycler.nextScreenFrame(currentFrame: unknown, screenFrames: [left, right]), left)
    }

    func test_axPosition_convertsBottomLeftOriginToTopLeftOrigin() {
        // 主屏高度 1080，目标屏幕在主屏正下方一块 1920x1080 的屏（NSScreen 坐标，左下角原点）。
        let targetFrame = CGRect(x: 0, y: -1080, width: 1920, height: 1080)
        let position = ScreenCycler.axPosition(forTargetFrame: targetFrame, primaryScreenHeight: 1080)

        XCTAssertEqual(position, CGPoint(x: 0, y: 1080))
    }

    func test_axPosition_targetScreenAboveOrigin() {
        // 目标屏幕在主屏（1440x900）右侧且顶部对齐主屏顶部。
        let targetFrame = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let position = ScreenCycler.axPosition(forTargetFrame: targetFrame, primaryScreenHeight: 900)

        XCTAssertEqual(position, CGPoint(x: 1440, y: -180))
    }

    // MARK: - translatedPosition

    func test_translatedPosition_preservesOffsetFromScreenOriginWhenMovingRight() {
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let toTheRight = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let windowPosition = CGPoint(x: 100, y: 50) // 靠近主屏左上角

        let translated = ScreenCycler.translatedPosition(windowPosition, fromScreenFrame: primary, toScreenFrame: toTheRight, primaryScreenHeight: 900)

        XCTAssertEqual(translated, CGPoint(x: 1540, y: -130))
    }

    func test_translatedPosition_sameScreen_isNoOp() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let windowPosition = CGPoint(x: 200, y: 120)

        let translated = ScreenCycler.translatedPosition(windowPosition, fromScreenFrame: screen, toScreenFrame: screen, primaryScreenHeight: 900)

        XCTAssertEqual(translated, windowPosition)
    }

    // MARK: - previousScreenFrame

    func test_previousScreenFrame_singleScreen_returnsNil() {
        let only = CGRect(x: 0, y: 0, width: 1440, height: 900)
        XCTAssertNil(ScreenCycler.previousScreenFrame(currentFrame: only, screenFrames: [only]))
    }

    func test_previousScreenFrame_twoScreens_isEquivalentToNext() {
        // 只有 2 块屏幕时，环形列表里往前走一格和往后走一格是同一个目的地。
        let left = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let right = CGRect(x: 1440, y: 0, width: 1920, height: 1080)

        XCTAssertEqual(ScreenCycler.previousScreenFrame(currentFrame: left, screenFrames: [left, right]), right)
        XCTAssertEqual(ScreenCycler.previousScreenFrame(currentFrame: right, screenFrames: [left, right]), left)
    }

    func test_previousScreenFrame_threeScreens_wrapsBackward() {
        let left = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let middle = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let right = CGRect(x: 3360, y: 0, width: 1920, height: 1080)

        XCTAssertEqual(ScreenCycler.previousScreenFrame(currentFrame: left, screenFrames: [left, middle, right]), right)
        XCTAssertEqual(ScreenCycler.previousScreenFrame(currentFrame: right, screenFrames: [left, middle, right]), middle)
        XCTAssertEqual(ScreenCycler.previousScreenFrame(currentFrame: middle, screenFrames: [left, middle, right]), left)
    }

    func test_previousScreenFrame_repeatedNMinusOneTimes_equalsOneNext() {
        // N 块屏幕时，连续按 N-1 次「上一个」应该落在跟按 1 次「下一个」相同的位置。
        let a = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let b = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let c = CGRect(x: 3360, y: 0, width: 1920, height: 1080)
        let screens = [a, b, c]

        let viaNext = ScreenCycler.nextScreenFrame(currentFrame: a, screenFrames: screens)

        var viaPrevious: CGRect? = a
        for _ in 0..<(screens.count - 1) {
            viaPrevious = ScreenCycler.previousScreenFrame(currentFrame: viaPrevious!, screenFrames: screens)
        }

        XCTAssertEqual(viaPrevious, viaNext)
    }
}
