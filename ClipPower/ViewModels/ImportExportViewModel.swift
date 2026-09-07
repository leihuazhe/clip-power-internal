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

    func export() async -> Data? {
        isBusy = true
        defer { isBusy = false }
        do {
            let scope = ExportScope(includeSoftHidden: includeSoftHidden, includeEncryptedHidden: includeEncryptedHidden)
            let password = exportPassword.isEmpty ? nil : exportPassword
            let data = try await service.export(scope: scope, exportPassword: password)
            statusMessage = "导出成功"
            return data
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
        statusMessage = "导入完成：新增 \(summary.imported)，覆盖 \(summary.overwritten)，新建副本 \(summary.duplicated)，"
            + "跳过 \(summary.skipped)，失败 \(summary.failed)"
        onImported()
    }
}
