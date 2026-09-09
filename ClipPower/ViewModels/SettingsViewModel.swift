import Foundation
import Combine
import AppKit

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published private(set) var clipboardHistoryCount: Int = 0
    @Published var selectedLanguage: AppLanguage = AppLanguageManager.current
    /// 语言切换后需要重启才能生效，这里只记录"待确认重启"的状态，交给 View 弹提示。
    @Published var pendingLanguageRestart = false

    @Published private(set) var isAccessibilityGranted: Bool = false
    @Published private(set) var isInputMonitoringGranted: Bool = false

    private let clipboardStore: ClipboardHistoryStore
    private var activationObserver: NSObjectProtocol?

    init(clipboardStore: ClipboardHistoryStore) {
        self.clipboardStore = clipboardStore
        reload()
        refreshPermissionStatus()
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.refreshPermissionStatus()
        }
    }

    func reload() {
        clipboardHistoryCount = (try? clipboardStore.count()) ?? 0
    }

    /// 用户从系统设置切回 App、或点了"前往系统设置"按钮回来时调用，重新查一次真实状态。
    func refreshPermissionStatus() {
        isAccessibilityGranted = PermissionsManager.isAccessibilityGranted()
        isInputMonitoringGranted = PermissionsManager.isInputMonitoringGranted()
    }

    func requestAccessibilityPermission() {
        PermissionsManager.requestAccessibilityIfNeeded()
    }

    func requestInputMonitoringPermission() {
        PermissionsManager.requestInputMonitoringIfNeeded { [weak self] _ in
            self?.refreshPermissionStatus()
        }
    }

    func openAccessibilitySettings() {
        PermissionsManager.openAccessibilitySettings()
    }

    func openInputMonitoringSettings() {
        PermissionsManager.openInputMonitoringSettings()
    }

    func clearClipboardHistory() {
        try? clipboardStore.clearAll()
        reload()
    }

    func languageDidChange(to language: AppLanguage) {
        guard language != AppLanguageManager.current else { return }
        AppLanguageManager.apply(language)
        pendingLanguageRestart = true
    }

    func restartNow() {
        AppLanguageManager.relaunch()
    }
}
