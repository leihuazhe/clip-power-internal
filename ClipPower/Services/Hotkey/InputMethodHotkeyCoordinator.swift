import Foundation
import KeyboardShortcuts

/// 把 `InputMethodBindingStore` 里的绑定同步成实际注册的全局热键。
///
/// `GlobalHotkeyManager.register` 底层是 `KeyboardShortcuts.onKeyUp(for:action:)`，重复对同一个
/// `Name` 调用会重复挂 handler，一次按键就会触发多次切换——所以这里用 `registeredIDs` 记录
/// 已经注册过的绑定，每次同步只对"新增"的调用 `register`，对"被删除"的调用 `disable`。
@MainActor
final class InputMethodHotkeyCoordinator {
    static let shared = InputMethodHotkeyCoordinator()

    private var store: InputMethodBindingStore?
    private var registeredIDs: Set<String> = []
    private var observer: NSObjectProtocol?

    func start(store: InputMethodBindingStore) {
        self.store = store
        syncRegistrations()
        observer = NotificationCenter.default.addObserver(
            forName: .inputMethodBindingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncRegistrations()
        }
    }

    private func syncRegistrations() {
        guard let bindings = try? store?.fetchAll() else { return }
        let currentIDs = Set(bindings.map(\.id))

        for removedID in registeredIDs.subtracting(currentIDs) {
            KeyboardShortcuts.disable(KeyboardShortcuts.Name("inputMethodHotkey_\(removedID)"))
        }

        for binding in bindings where !registeredIDs.contains(binding.id) {
            let inputSourceID = binding.inputSourceID
            GlobalHotkeyManager.shared.register(binding.shortcutName) {
                InputSourceManager.select(inputSourceID: inputSourceID)
            }
        }

        registeredIDs = currentIDs
    }
}
