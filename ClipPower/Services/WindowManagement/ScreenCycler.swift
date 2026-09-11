import CoreGraphics

/// 纯几何计算：给定屏幕列表选出「上一块/下一块屏幕」，以及 AX 坐标系换算。
/// 不依赖 `NSScreen`/AX API，方便单测；真机相关的 `NSScreen`/AXUIElement 调用在 `FullscreenWindowMover` 里。
enum ScreenCycler {
    /// 按 x 坐标从左到右排好序，在这个环形列表里从 `currentFrame` 往后走一格。
    /// 只有 1 块屏幕时返回 nil（没有"下一个"）。
    static func nextScreenFrame(currentFrame: CGRect, screenFrames: [CGRect]) -> CGRect? {
        frame(offsetBy: 1, from: currentFrame, in: screenFrames)
    }

    /// 跟 `nextScreenFrame` 相反方向；两者都是同一个环形列表上的循环移动，
    /// 所以只有 2 块屏幕时二者等价，N 块屏幕时连续按 N-1 次「上一个」等于按 1 次「下一个」。
    static func previousScreenFrame(currentFrame: CGRect, screenFrames: [CGRect]) -> CGRect? {
        frame(offsetBy: -1, from: currentFrame, in: screenFrames)
    }

    /// `NSScreen.frame` 是左下角原点、y 向上；Accessibility API 的全局坐标是左上角原点、y 向下。
    /// 用主屏高度做一次翻转换算，x 轴方向两者一致不需要处理。
    static func axPosition(forTargetFrame targetFrame: CGRect, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: targetFrame.minX, y: primaryScreenHeight - targetFrame.maxY)
    }

    /// 非全屏窗口跨屏移动时用：把 `position`（AX 坐标）相对 `fromScreenFrame` 的偏移量，
    /// 原样搬到 `toScreenFrame` 上——窗口在原屏幕靠左上角，搬过去之后还是靠左上角。
    /// 不做越界裁剪：目标屏幕比原屏幕小的话窗口可能有一部分伸到屏幕外，跟大多数窗口管理工具的简单实现一致。
    static func translatedPosition(_ position: CGPoint, fromScreenFrame: CGRect, toScreenFrame: CGRect, primaryScreenHeight: CGFloat) -> CGPoint {
        let fromOrigin = axPosition(forTargetFrame: fromScreenFrame, primaryScreenHeight: primaryScreenHeight)
        let toOrigin = axPosition(forTargetFrame: toScreenFrame, primaryScreenHeight: primaryScreenHeight)
        let offset = CGPoint(x: position.x - fromOrigin.x, y: position.y - fromOrigin.y)
        return CGPoint(x: toOrigin.x + offset.x, y: toOrigin.y + offset.y)
    }

    /// 找不到 `currentFrame`（比如屏幕刚好在这一瞬间被拔掉）时退回最左边的屏幕，而不是报错，
    /// 上一个/下一个共用这一条兜底逻辑。
    private static func frame(offsetBy offset: Int, from currentFrame: CGRect, in screenFrames: [CGRect]) -> CGRect? {
        let sorted = screenFrames.sorted { $0.origin.x < $1.origin.x }
        let count = sorted.count
        guard count > 1 else { return nil }
        guard let index = sorted.firstIndex(of: currentFrame) else { return sorted.first }
        return sorted[((index + offset) % count + count) % count]
    }
}
