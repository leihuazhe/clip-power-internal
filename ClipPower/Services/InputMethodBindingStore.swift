import Foundation
import GRDB

extension Notification.Name {
    /// 输入法快捷键绑定被创建/删除时发出，`InputMethodHotkeyCoordinator` 借此知道要
    /// 重新同步热键注册状态了。
    static let inputMethodBindingsDidChange = Notification.Name("ClipPower.inputMethodBindingsDidChange")
}

/// 输入法快捷键绑定的数据层 facade，UI 层只通过它访问数据库。
final class InputMethodBindingStore: Sendable {
    let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    @discardableResult
    func create(_ input: InputMethodBinding) throws -> InputMethodBinding {
        var binding = input
        let now = Date()
        binding.createdAt = now
        binding.updatedAt = now
        try dbQueue.write { db in
            try binding.insert(db)
        }
        postDidChange()
        return binding
    }

    func delete(id: String) throws {
        try dbQueue.write { db in
            _ = try InputMethodBinding.deleteOne(db, key: id)
        }
        postDidChange()
    }

    func fetchAll() throws -> [InputMethodBinding] {
        try dbQueue.read { db in
            try InputMethodBinding
                .order(Column("sortOrder"), Column("createdAt"))
                .fetchAll(db)
        }
    }

    private func postDidChange() {
        NotificationCenter.default.post(name: .inputMethodBindingsDidChange, object: nil)
    }
}
