import AppKit
@preconcurrency import ApplicationServices

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
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
