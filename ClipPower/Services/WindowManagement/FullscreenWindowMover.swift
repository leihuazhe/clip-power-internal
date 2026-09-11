import AppKit
@preconcurrency import ApplicationServices

/// 把前台窗口移动到上一块/下一块屏幕。全屏窗口跑在独立 Space 上，AX 不能直接改它的
/// position/size，只能退出全屏 → 挪到目标屏幕 → 重新全屏（模拟用户拖标题条到另一屏，
/// 这一步对某些 App——尤其是 Electron 套壳应用——不一定生效，见下面 `move` 里的日志）；
/// 非全屏窗口不用这套动画，直接原样把窗口在屏幕内的相对位置搬过去。
@MainActor
enum FullscreenWindowMover {
    /// 退出全屏和重新全屏都有系统动画，这两步之间必须等动画播完，
    /// 否则 `kAXPositionAttribute`/`kAXFullScreenAttribute` 的下一次调用会作用在
    /// 还没稳定下来的窗口状态上而静默失败。具体时长没法在这个环境里实测，
    /// 先给一个偏保守的经验值，如果实机测试发现不够再调大。
    private static let animationSettleDelay: TimeInterval = 0.5

    /// 防抖：退出全屏→挪动→重新全屏是一套跨越多次系统动画的时序，
    /// 用户连续按快捷键会把两套时序交叠在一起，导致窗口卡在中间状态。
    private static var isMoving = false

    /// `kAXFullScreenAttribute` 不是公开 SDK 常量（`ApplicationServices` 头文件里没有），
    /// 但这个字符串是系统原生全屏窗口实际暴露的 AX 属性名，Rectangle/BetterSnapTool 等
    /// 第三方窗口管理工具都是这样直接用字面量访问的。
    private static let axFullScreenAttribute = "AXFullScreen" as CFString

    static func moveFrontmostWindowToNextScreen() {
        move { currentFrame, screenFrames in
            ScreenCycler.nextScreenFrame(currentFrame: currentFrame, screenFrames: screenFrames)
        }
    }

    static func moveFrontmostWindowToPreviousScreen() {
        move { currentFrame, screenFrames in
            ScreenCycler.previousScreenFrame(currentFrame: currentFrame, screenFrames: screenFrames)
        }
    }

    private static func move(pickTargetFrame: (CGRect, [CGRect]) -> CGRect?) {
        guard !isMoving else { return }
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            log("没拿到前台 App 的 pid")
            return
        }

        guard let window = focusedWindow(forPID: pid) else {
            log("没拿到前台 App 的 focused window（可能没有辅助功能权限）")
            return
        }

        guard let currentScreen = NSScreen.main,
              let primaryScreenHeight = NSScreen.screens.first?.frame.height,
              let targetFrame = pickTargetFrame(currentScreen.frame, NSScreen.screens.map(\.frame))
        else {
            log("没找到目标屏幕（可能只有 1 块屏幕）")
            return
        }

        if isFullScreen(window) {
            isMoving = true
            log("退出全屏")
            setFullScreen(window, false)

            DispatchQueue.main.asyncAfter(deadline: .now() + animationSettleDelay) {
                // 退出全屏之后，原来那个 AXUIElement 大概率已经失效——
                // 系统在切出全屏 Space 的同时会换一个新的窗口对象，继续用旧引用
                // 设置 position/再次全屏会静默失败，表现就是"挪过去之后卡在非全屏"。
                guard let refetchedWindow = focusedWindow(forPID: pid) else {
                    log("退出全屏后重新取 focused window 失败，放弃后续步骤")
                    isMoving = false
                    return
                }

                let axPosition = ScreenCycler.axPosition(forTargetFrame: targetFrame, primaryScreenHeight: primaryScreenHeight)
                log("挪到目标位置 \(axPosition)")
                setPosition(refetchedWindow, axPosition)

                DispatchQueue.main.asyncAfter(deadline: .now() + animationSettleDelay) {
                    guard let windowToRefullscreen = focusedWindow(forPID: pid) else {
                        log("挪动后重新取 focused window 失败，没法重新全屏")
                        isMoving = false
                        return
                    }
                    log("重新全屏")
                    setFullScreen(windowToRefullscreen, true)
                    isMoving = false
                }
            }
        } else {
            guard let currentPosition = position(of: window) else {
                log("非全屏窗口读不到当前 position")
                return
            }
            let newPosition = ScreenCycler.translatedPosition(
                currentPosition,
                fromScreenFrame: currentScreen.frame,
                toScreenFrame: targetFrame,
                primaryScreenHeight: primaryScreenHeight
            )
            log("非全屏窗口直接挪到 \(newPosition)")
            setPosition(window, newPosition)
        }
    }

    private static func focusedWindow(forPID pid: pid_t) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(pid)
        var focusedWindowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindowRef) == .success,
              let focusedWindowRef else { return nil }
        return (focusedWindowRef as! AXUIElement)
    }

    private static func isFullScreen(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, axFullScreenAttribute, &value) == .success else {
            return false
        }
        return (value as? Bool) ?? false
    }

    @discardableResult
    private static func setFullScreen(_ window: AXUIElement, _ fullScreen: Bool) -> AXError {
        let result = AXUIElementSetAttributeValue(window, axFullScreenAttribute, fullScreen ? kCFBooleanTrue : kCFBooleanFalse)
        if result != .success {
            log("设置 AXFullScreen=\(fullScreen) 失败：\(result.rawValue)")
        }
        return result
    }

    private static func position(of window: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &value) == .success,
              let value else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    @discardableResult
    private static func setPosition(_ window: AXUIElement, _ position: CGPoint) -> AXError {
        var mutablePosition = position
        guard let value = AXValueCreate(.cgPoint, &mutablePosition) else { return .failure }
        let result = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        if result != .success {
            log("设置 position=\(position) 失败：\(result.rawValue)")
        }
        return result
    }

    private static func log(_ message: String) {
        print("[FullscreenWindowMover] \(message)")
    }
}
