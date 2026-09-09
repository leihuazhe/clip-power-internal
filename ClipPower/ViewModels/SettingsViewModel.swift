import Foundation
import Combine

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published private(set) var clipboardHistoryCount: Int = 0
    @Published var selectedLanguage: AppLanguage = AppLanguageManager.current
    /// 语言切换后需要重启才能生效，这里只记录"待确认重启"的状态，交给 View 弹提示。
    @Published var pendingLanguageRestart = false

    private let clipboardStore: ClipboardHistoryStore

    init(clipboardStore: ClipboardHistoryStore) {
        self.clipboardStore = clipboardStore
        reload()
    }

    func reload() {
        clipboardHistoryCount = (try? clipboardStore.count()) ?? 0
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
