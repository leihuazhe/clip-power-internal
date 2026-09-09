import AppKit
@preconcurrency import ApplicationServices
import IOKit.hid

enum PermissionsManager {
    static func isAccessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    /// 若尚未授权，触发系统的辅助功能授权提示对话框。
    @discardableResult
    static func requestAccessibilityIfNeeded() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeRetainedValue() as String
        let options: NSDictionary = [key: true]
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        openSystemSettings(anchor: "Privacy_Accessibility")
    }

    /// 纯查询、同步、不弹窗——`TextExpansionMonitor` 依赖的全局按键监听归属这项权限，
    /// 跟辅助功能是两个独立的 TCC 权限桶。
    static func isInputMonitoringGranted() -> Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// 只有当前状态是"从未问过"时系统才会真正弹窗；用户已经明确拒绝过时不会重复弹，
    /// 只能引导去系统设置手动打开——所以调用方不应只依赖这个方法，还要提供
    /// `openInputMonitoringSettings()` 的手动路径。放到后台队列调用避免可能的阻塞。
    static func requestInputMonitoringIfNeeded(completion: (@MainActor @Sendable (Bool) -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
            if let completion {
                DispatchQueue.main.async { completion(result) }
            }
        }
    }

    static func openInputMonitoringSettings() {
        openSystemSettings(anchor: "Privacy_ListenEvent")
    }

    private static func openSystemSettings(anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
