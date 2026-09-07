import Foundation
import Combine

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published private(set) var clipboardHistoryCount: Int = 0

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
}
