import Foundation
import CryptoKit

enum ImportConflictPolicy: Hashable, CaseIterable, Sendable {
    case skip
    case overwrite
    case duplicateAsNew

    var displayName: String {
        switch self {
        case .skip: return "跳过"
        case .overwrite: return "覆盖"
        case .duplicateAsNew: return "新建副本"
        }
    }
}

enum ImportExportError: Error {
    case passwordRequired
    case unsupportedFormatVersion(Int)
}

struct ImportSummary: Equatable, Sendable {
    var imported = 0
    var skipped = 0
    var overwritten = 0
    var duplicated = 0
    var failed = 0
}

/// 导出范围：普通条目总是包含；软隐藏/加密隐藏可分别选择是否包含。
struct ExportScope: Sendable {
    var includeSoftHidden: Bool
    var includeEncryptedHidden: Bool

    static let all = ExportScope(includeSoftHidden: true, includeEncryptedHidden: true)
    static let normalOnly = ExportScope(includeSoftHidden: false, includeEncryptedHidden: false)
}

/// 负责导出/导入 JSON 包；加密隐藏内容的密码保护与冲突处理策略见 docs/design.md。
final class ImportExportService: Sendable {
    static let currentFormatVersion = 1
    private static let pbkdf2Iterations = 200_000

    private let store: SnippetStore
    private let contentRevealer: SnippetContentRevealing

    init(store: SnippetStore, contentRevealer: SnippetContentRevealing = SnippetEncryptionService()) {
        self.store = store
        self.contentRevealer = contentRevealer
    }

    // MARK: - Export

    func export(scope: ExportScope, exportPassword: String?) async throws -> Data {
        let snippets = try store.fetchActive()

        var exportKey: SymmetricKey?
        var kdfInfo: ExportKDFInfo?
        if scope.includeEncryptedHidden, let exportPassword, !exportPassword.isEmpty {
            let salt = PasswordKeyDerivation.randomSalt()
            exportKey = PasswordKeyDerivation.deriveKey(password: exportPassword, salt: salt, iterations: Self.pbkdf2Iterations)
            kdfInfo = ExportKDFInfo(algorithm: "PBKDF2-SHA256", salt: salt, iterations: Self.pbkdf2Iterations)
        }

        var exported: [ExportedSnippet] = []
        for snippet in snippets {
            if let item = try await exportedSnippet(for: snippet, scope: scope, exportKey: exportKey) {
                exported.append(item)
            }
        }

        let package = ExportPackage(
            formatVersion: Self.currentFormatVersion,
            exportedAt: Date(),
            requiresExportPassword: exportKey != nil,
            exportKDF: kdfInfo,
            snippets: exported
        )
        return try Self.makeEncoder().encode(package)
    }

    private func exportedSnippet(
        for snippet: Snippet,
        scope: ExportScope,
        exportKey: SymmetricKey?
    ) async throws -> ExportedSnippet? {
        var base = ExportedSnippet(
            id: snippet.id,
            name: snippet.name,
            keyword: snippet.keyword,
            contentType: snippet.contentType,
            visibility: snippet.visibility,
            tags: snippet.tags,
            createdAt: snippet.createdAt,
            updatedAt: snippet.updatedAt
        )

        switch snippet.visibility {
        case .normal:
            base.content = snippet.plainContent
            return base

        case .softHidden:
            guard scope.includeSoftHidden else { return nil }
            base.content = snippet.plainContent
            return base

        case .encryptedHidden:
            guard scope.includeEncryptedHidden, let cipherContent = snippet.cipherContent else { return nil }
            if let exportKey {
                let plaintext = try await contentRevealer.reveal(snippet)
                base.passwordProtectedCipherContent = try SnippetCipher.encrypt(plaintext: plaintext, using: exportKey)
            } else {
                base.deviceBoundCipherContent = cipherContent
            }
            return base
        }
    }

    // MARK: - Import

    func importPackage(from data: Data, importPassword: String?, conflictPolicy: ImportConflictPolicy) async -> ImportSummary {
        var summary = ImportSummary()

        guard let package = try? Self.makeDecoder().decode(ExportPackage.self, from: data),
              package.formatVersion == Self.currentFormatVersion else {
            summary.failed = 1
            return summary
        }

        var importKey: SymmetricKey?
        if package.requiresExportPassword {
            guard let importPassword, !importPassword.isEmpty, let kdf = package.exportKDF else {
                summary.failed = package.snippets.count
                return summary
            }
            importKey = PasswordKeyDerivation.deriveKey(password: importPassword, salt: kdf.salt, iterations: kdf.iterations)
        }

        for exportedSnippet in package.snippets {
            await importOne(exportedSnippet, importKey: importKey, conflictPolicy: conflictPolicy, summary: &summary)
        }
        return summary
    }

    private func importOne(
        _ exported: ExportedSnippet,
        importKey: SymmetricKey?,
        conflictPolicy: ImportConflictPolicy,
        summary: inout ImportSummary
    ) async {
        do {
            var snippet = try await resolvedSnippet(from: exported, importKey: importKey)

            if let keyword = snippet.keyword, let existing = try store.fetchByKeyword(keyword), existing.id != snippet.id {
                switch conflictPolicy {
                case .skip:
                    summary.skipped += 1
                    return
                case .overwrite:
                    snippet.id = existing.id
                    _ = try store.update(snippet)
                    summary.overwritten += 1
                    return
                case .duplicateAsNew:
                    snippet.id = UUID().uuidString
                    snippet.keyword = "\(keyword)-imported"
                    _ = try store.create(snippet)
                    summary.duplicated += 1
                    return
                }
            }

            _ = try store.create(snippet)
            summary.imported += 1
        } catch {
            summary.failed += 1
        }
    }

    private func resolvedSnippet(from exported: ExportedSnippet, importKey: SymmetricKey?) async throws -> Snippet {
        var snippet = Snippet(
            id: exported.id,
            name: exported.name,
            keyword: exported.keyword,
            contentType: exported.contentType,
            visibility: .normal,
            tags: exported.tags,
            createdAt: exported.createdAt,
            updatedAt: exported.updatedAt
        )

        switch exported.visibility {
        case .normal, .softHidden:
            snippet.plainContent = exported.content
            snippet.visibility = exported.visibility
            return snippet

        case .encryptedHidden:
            if let passwordProtected = exported.passwordProtectedCipherContent {
                guard let importKey else { throw ImportExportError.passwordRequired }
                let plaintext = try SnippetCipher.decrypt(cipherContent: passwordProtected, using: importKey)
                snippet.plainContent = plaintext
                return try await contentRevealer.hide(snippet)
            }

            if let deviceBoundCipher = exported.deviceBoundCipherContent {
                // 只有回到同一台机器、本机 DEK 未变时，才可能解开设备绑定密文。
                var probe = snippet
                probe.cipherContent = deviceBoundCipher
                probe.visibility = .encryptedHidden
                let plaintext = try await contentRevealer.reveal(probe)
                snippet.plainContent = plaintext
                return try await contentRevealer.hide(snippet)
            }

            throw ImportExportError.passwordRequired
        }
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
