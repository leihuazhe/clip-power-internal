import Foundation
@testable import ClipPower

/// 假的加解密实现，只做内存映射，完全不触碰 Keychain/Secure Enclave/Touch ID，
/// 用于单元测试 ImportExportService 的打包/冲突处理逻辑（真实加解密已在
/// SnippetCipherTests / KeyManagerWrapTests 里单独验证）。
final class FakeSnippetContentRevealing: SnippetContentRevealing, @unchecked Sendable {
    private var storageByMarker: [String: String] = [:]
    var shouldFailReveal = false

    func hide(_ snippet: Snippet) async throws -> Snippet {
        guard let plaintext = snippet.plainContent else {
            throw SnippetEncryptionError.missingPlainContent
        }
        let marker = UUID().uuidString
        storageByMarker[marker] = plaintext

        var result = snippet
        result.cipherContent = Data(marker.utf8)
        result.plainContent = nil
        result.keyID = "fake-key"
        result.visibility = .encryptedHidden
        return result
    }

    func reveal(_ snippet: Snippet) async throws -> String {
        if shouldFailReveal {
            throw SnippetEncryptionError.missingCipherContent
        }
        guard let cipherContent = snippet.cipherContent,
              let marker = String(data: cipherContent, encoding: .utf8),
              let plaintext = storageByMarker[marker] else {
            throw SnippetEncryptionError.missingCipherContent
        }
        return plaintext
    }

    func unhide(_ snippet: Snippet) async throws -> Snippet {
        let plaintext = try await reveal(snippet)
        var result = snippet
        result.plainContent = plaintext
        result.cipherContent = nil
        result.keyID = nil
        result.visibility = .normal
        return result
    }
}
