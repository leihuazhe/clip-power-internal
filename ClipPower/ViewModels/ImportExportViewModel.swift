import Foundation
import Combine

@MainActor
final class ImportExportViewModel: ObservableObject {
    @Published var includeSoftHidden = true
    @Published var includeEncryptedHidden = true
    @Published var exportPassword = ""
    @Published var importPassword = ""
    @Published var conflictPolicy: ImportConflictPolicy = .skip
    @Published var statusMessage: String?
    @Published var isBusy = false

    private let service: ImportExportService
    private let onImported: () -> Void

    init(store: SnippetStore, onImported: @escaping () -> Void = {}) {
        self.service = ImportExportService(store: store)
        self.onImported = onImported
    }

    /// 只生成导出数据，不在这里设置"成功"提示——真正的保存动作（用户在 `NSSavePanel`
    /// 里选位置并点 Save）发生在调用方，成功文案应该等那一步真的落盘之后才出现，
    /// 否则会在用户还没保存时就先看到"导出成功"，见 BUG List 记录。
    func export() async -> Data? {
        isBusy = true
        defer { isBusy = false }
        do {
            let scope = ExportScope(includeSoftHidden: includeSoftHidden, includeEncryptedHidden: includeEncryptedHidden)
            let password = exportPassword.isEmpty ? nil : exportPassword
            return try await service.export(scope: scope, exportPassword: password)
        } catch {
            statusMessage = "导出失败：\(error.localizedDescription)"
            return nil
        }
    }

    func importFile(data: Data) async {
        isBusy = true
        defer { isBusy = false }
        let password = importPassword.isEmpty ? nil : importPassword
        let summary = await service.importPackage(from: data, importPassword: password, conflictPolicy: conflictPolicy)
        statusMessage = summaryMessage(summary)
        onImported()
    }

    /// 导入 Raycast 官方导出的 Snippets JSON（`[{ "name", "text", "keyword"? }, ...]`）。
    func importRaycastFile(data: Data) async {
        isBusy = true
        defer { isBusy = false }
        let summary = await service.importRaycastSnippets(from: data, conflictPolicy: conflictPolicy)
        statusMessage = summaryMessage(summary)
        onImported()
    }

    /// 导出成 Raycast 官方 Snippets 的格式，只包含公开（未隐藏）片段。
    /// 同 `export()`：不在这里设置成功提示，交给调用方在用户真正保存文件之后再设置。
    func exportRaycastFile() async -> Data? {
        isBusy = true
        defer { isBusy = false }
        do {
            return try service.exportRaycastSnippets()
        } catch {
            statusMessage = "导出失败：\(error.localizedDescription)"
            return nil
        }
    }

    private func summaryMessage(_ summary: ImportSummary) -> String {
        "导入完成：新增 \(summary.imported)，覆盖 \(summary.overwritten)，新建副本 \(summary.duplicated)，"
            + "跳过 \(summary.skipped)，失败 \(summary.failed)"
    }
}
