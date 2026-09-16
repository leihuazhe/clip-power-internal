import Foundation

@MainActor
final class InputMethodHotkeysViewModel: ObservableObject {
    @Published private(set) var bindings: [InputMethodBinding] = []
    @Published private(set) var availableInputSources: [InputSourceInfo] = []
    @Published var errorMessage: String?

    private let store: InputMethodBindingStore

    init(store: InputMethodBindingStore) {
        self.store = store
        reload()
    }

    func reload() {
        do {
            bindings = try store.fetchAll()
        } catch {
            errorMessage = localizedFormat("loadInputMethodBindingsFailedFormat", error.localizedDescription)
        }
    }

    /// 打开"添加输入法"弹层前调用一次：只列出已启用、且还没被绑定过的输入源。
    func reloadAvailableInputSources() {
        let boundIDs = Set(bindings.map(\.inputSourceID))
        availableInputSources = InputSourceManager.listSelectable()
            .filter { !boundIDs.contains($0.id) }
    }

    func addBinding(_ inputSource: InputSourceInfo) {
        do {
            _ = try store.create(
                InputMethodBinding(
                    inputSourceID: inputSource.id,
                    displayName: inputSource.localizedName,
                    sortOrder: bindings.count
                )
            )
            reload()
        } catch {
            errorMessage = localizedFormat("saveInputMethodBindingFailedFormat", error.localizedDescription)
        }
    }

    func removeBinding(_ binding: InputMethodBinding) {
        do {
            try store.delete(id: binding.id)
            reload()
        } catch {
            errorMessage = localizedFormat("deleteInputMethodBindingFailedFormat", error.localizedDescription)
        }
    }
}
