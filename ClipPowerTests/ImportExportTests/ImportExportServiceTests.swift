import XCTest
import GRDB
@testable import ClipPower

final class ImportExportServiceTests: XCTestCase {
    private func makeStore() throws -> SnippetStore {
        let dbQueue = try DatabaseQueue()
        _ = DatabaseManager(dbQueue: dbQueue)
        return SnippetStore(dbQueue: dbQueue)
    }

    func testExportImportRoundTripNormalAndSoftHidden() async throws {
        let sourceStore = try makeStore()
        _ = try sourceStore.create(Snippet(name: "地址", keyword: "addr", plainContent: "123 Main St"))
        _ = try sourceStore.create(Snippet(name: "隐藏笔记", keyword: "note", plainContent: "私密笔记", visibility: .softHidden))

        let exportService = ImportExportService(store: sourceStore, contentRevealer: FakeSnippetContentRevealing())
        let data = try await exportService.export(scope: .all, exportPassword: nil)

        let destinationStore = try makeStore()
        let importService = ImportExportService(store: destinationStore, contentRevealer: FakeSnippetContentRevealing())
        let summary = await importService.importPackage(from: data, importPassword: nil, conflictPolicy: .skip)

        XCTAssertEqual(summary.imported, 2)
        XCTAssertEqual(summary.failed, 0)

        let all = try destinationStore.fetchActive()
        XCTAssertEqual(all.first { $0.visibility == .normal }?.plainContent, "123 Main St")

        let hidden = all.first { $0.visibility == .softHidden }
        XCTAssertEqual(hidden?.plainContent, "私密笔记")
    }

    func testExportScopeExcludesSoftHiddenWhenNotRequested() async throws {
        let store = try makeStore()
        _ = try store.create(Snippet(name: "公开"))
        _ = try store.create(Snippet(name: "软隐藏", visibility: .softHidden))

        let exportService = ImportExportService(store: store, contentRevealer: FakeSnippetContentRevealing())
        let data = try await exportService.export(scope: .normalOnly, exportPassword: nil)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let package = try decoder.decode(ExportPackage.self, from: data)

        XCTAssertEqual(package.snippets.count, 1)
        XCTAssertEqual(package.snippets.first?.visibility, .normal)
    }

    func testExportEncryptedHiddenWithPasswordAndImportSucceeds() async throws {
        let sourceStore = try makeStore()
        let revealer = FakeSnippetContentRevealing()
        var secret = try sourceStore.create(Snippet(name: "API Key", plainContent: "sk-secret-value"))
        secret = try await revealer.hide(secret)
        _ = try sourceStore.update(secret)

        let exportService = ImportExportService(store: sourceStore, contentRevealer: revealer)
        let data = try await exportService.export(scope: .all, exportPassword: "correct-password")

        let destinationStore = try makeStore()
        let importRevealer = FakeSnippetContentRevealing()
        let importService = ImportExportService(store: destinationStore, contentRevealer: importRevealer)
        let summary = await importService.importPackage(from: data, importPassword: "correct-password", conflictPolicy: .skip)

        XCTAssertEqual(summary.imported, 1)
        XCTAssertEqual(summary.failed, 0)

        let hidden = try destinationStore.fetchActive()
        XCTAssertEqual(hidden.count, 1)
        XCTAssertEqual(hidden.first?.visibility, .encryptedHidden)

        let revealedPlaintext = try await importRevealer.reveal(hidden.first!)
        XCTAssertEqual(revealedPlaintext, "sk-secret-value")
    }

    func testImportWithWrongExportPasswordFails() async throws {
        let sourceStore = try makeStore()
        let revealer = FakeSnippetContentRevealing()
        var secret = try sourceStore.create(Snippet(name: "API Key", plainContent: "sk-secret-value"))
        secret = try await revealer.hide(secret)
        _ = try sourceStore.update(secret)

        let exportService = ImportExportService(store: sourceStore, contentRevealer: revealer)
        let data = try await exportService.export(scope: .all, exportPassword: "correct-password")

        let destinationStore = try makeStore()
        let importService = ImportExportService(store: destinationStore, contentRevealer: FakeSnippetContentRevealing())
        let summary = await importService.importPackage(from: data, importPassword: "wrong-password", conflictPolicy: .skip)

        XCTAssertEqual(summary.imported, 0)
        XCTAssertEqual(summary.failed, 1)
    }

    func testImportMissingPasswordFailsAllEncryptedEntries() async throws {
        let sourceStore = try makeStore()
        let revealer = FakeSnippetContentRevealing()
        var secret = try sourceStore.create(Snippet(name: "API Key", plainContent: "sk-secret-value"))
        secret = try await revealer.hide(secret)
        _ = try sourceStore.update(secret)

        let exportService = ImportExportService(store: sourceStore, contentRevealer: revealer)
        let data = try await exportService.export(scope: .all, exportPassword: "correct-password")

        let destinationStore = try makeStore()
        let importService = ImportExportService(store: destinationStore, contentRevealer: FakeSnippetContentRevealing())
        let summary = await importService.importPackage(from: data, importPassword: nil, conflictPolicy: .skip)

        XCTAssertEqual(summary.imported, 0)
        XCTAssertEqual(summary.failed, 1)
    }

    func testImportDeviceBoundEncryptedSucceedsWhenRevealerCanDecrypt() async throws {
        let sourceStore = try makeStore()
        let revealer = FakeSnippetContentRevealing()
        var secret = try sourceStore.create(Snippet(name: "本机密钥", plainContent: "device-bound-secret"))
        secret = try await revealer.hide(secret)
        _ = try sourceStore.update(secret)

        // 不设置导出密码：模拟"备份到同一台机器"场景，导入时复用同一个 revealer 实例（同一"设备"）。
        let exportService = ImportExportService(store: sourceStore, contentRevealer: revealer)
        let data = try await exportService.export(scope: .all, exportPassword: nil)

        let destinationStore = try makeStore()
        let importService = ImportExportService(store: destinationStore, contentRevealer: revealer)
        let summary = await importService.importPackage(from: data, importPassword: nil, conflictPolicy: .skip)

        XCTAssertEqual(summary.imported, 1)
        XCTAssertEqual(summary.failed, 0)
    }

    func testImportDeviceBoundEncryptedFailsOnDifferentDevice() async throws {
        let sourceStore = try makeStore()
        let revealer = FakeSnippetContentRevealing()
        var secret = try sourceStore.create(Snippet(name: "本机密钥", plainContent: "device-bound-secret"))
        secret = try await revealer.hide(secret)
        _ = try sourceStore.update(secret)

        let exportService = ImportExportService(store: sourceStore, contentRevealer: revealer)
        let data = try await exportService.export(scope: .all, exportPassword: nil)

        // 换一台"设备"：全新的 revealer 实例，无法解开设备绑定密文。
        let destinationStore = try makeStore()
        let importService = ImportExportService(store: destinationStore, contentRevealer: FakeSnippetContentRevealing())
        let summary = await importService.importPackage(from: data, importPassword: nil, conflictPolicy: .skip)

        XCTAssertEqual(summary.imported, 0)
        XCTAssertEqual(summary.failed, 1)
    }

    func testImportConflictSkipKeepsExisting() async throws {
        let sourceStore = try makeStore()
        _ = try sourceStore.create(Snippet(name: "远端版本", keyword: "dup", plainContent: "remote"))

        let exportService = ImportExportService(store: sourceStore, contentRevealer: FakeSnippetContentRevealing())
        let data = try await exportService.export(scope: .all, exportPassword: nil)

        let destinationStore = try makeStore()
        _ = try destinationStore.create(Snippet(name: "本地版本", keyword: "dup", plainContent: "local"))
        let importService = ImportExportService(store: destinationStore, contentRevealer: FakeSnippetContentRevealing())
        let summary = await importService.importPackage(from: data, importPassword: nil, conflictPolicy: .skip)

        XCTAssertEqual(summary.skipped, 1)
        let active = try destinationStore.fetchActive()
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active.first?.plainContent, "local")
    }

    func testImportConflictOverwriteReplacesExisting() async throws {
        let sourceStore = try makeStore()
        _ = try sourceStore.create(Snippet(name: "远端版本", keyword: "dup", plainContent: "remote"))

        let exportService = ImportExportService(store: sourceStore, contentRevealer: FakeSnippetContentRevealing())
        let data = try await exportService.export(scope: .all, exportPassword: nil)

        let destinationStore = try makeStore()
        _ = try destinationStore.create(Snippet(name: "本地版本", keyword: "dup", plainContent: "local"))
        let importService = ImportExportService(store: destinationStore, contentRevealer: FakeSnippetContentRevealing())
        let summary = await importService.importPackage(from: data, importPassword: nil, conflictPolicy: .overwrite)

        XCTAssertEqual(summary.overwritten, 1)
        let active = try destinationStore.fetchActive()
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active.first?.plainContent, "remote")
    }

    func testImportConflictDuplicateAsNewKeepsBoth() async throws {
        let sourceStore = try makeStore()
        _ = try sourceStore.create(Snippet(name: "远端版本", keyword: "dup", plainContent: "remote"))

        let exportService = ImportExportService(store: sourceStore, contentRevealer: FakeSnippetContentRevealing())
        let data = try await exportService.export(scope: .all, exportPassword: nil)

        let destinationStore = try makeStore()
        _ = try destinationStore.create(Snippet(name: "本地版本", keyword: "dup", plainContent: "local"))
        let importService = ImportExportService(store: destinationStore, contentRevealer: FakeSnippetContentRevealing())
        let summary = await importService.importPackage(from: data, importPassword: nil, conflictPolicy: .duplicateAsNew)

        XCTAssertEqual(summary.duplicated, 1)
        XCTAssertEqual(summary.imported, 0)
        let active = try destinationStore.fetchActive()
        XCTAssertEqual(active.count, 2)
        XCTAssertTrue(active.contains { $0.keyword == "dup-imported" })
    }
}
