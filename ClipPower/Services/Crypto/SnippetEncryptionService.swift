import Foundation

enum SnippetEncryptionError: Error {
    case missingPlainContent
    case missingCipherContent
}

/// 抽象出 hide/reveal，让依赖它的上层逻辑（如 ImportExportService 的冲突处理、
/// 打包逻辑）可以在单元测试里注入不触碰 Keychain/Touch ID 的假实现。
/// 真实 SnippetEncryptionService 的路径需要在图形界面下手动验证（见 docs/design.md）。
protocol SnippetContentRevealing: Sendable {
    func hide(_ snippet: Snippet) async throws -> Snippet
    func reveal(_ snippet: Snippet) async throws -> String
    func unhide(_ snippet: Snippet) async throws -> Snippet
}

/// 面向 ViewModel 的加解密协调层：串联 BiometricGate → KeyManager → SnippetCipher。
final class SnippetEncryptionService: SnippetContentRevealing, Sendable {
    private let keyManager: KeyManager
    private let biometricGate: BiometricGate

    init(keyManager: KeyManager = .shared, biometricGate: BiometricGate = .shared) {
        self.keyManager = keyManager
        self.biometricGate = biometricGate
    }

    /// 把明文内容加密隐藏；返回已填好 cipherContent/keyID、清空 plainContent、
    /// visibility 置为 encryptedHidden 的新 snippet，调用方负责持久化。
    func hide(_ snippet: Snippet) async throws -> Snippet {
        guard let plainContent = snippet.plainContent else {
            throw SnippetEncryptionError.missingPlainContent
        }

        let keyManager = self.keyManager
        let cipherContent = try await biometricGate.authenticate(reason: String(localized: "启用加密隐藏需要验证身份")) { context in
            try keyManager.setupEncryptionIfNeeded(context: context)
            let dek = try keyManager.unwrapDEK(context: context)
            return try SnippetCipher.encrypt(plaintext: plainContent, using: dek)
        }

        var result = snippet
        result.cipherContent = cipherContent
        result.plainContent = nil
        result.keyID = KeyManager.currentKeyID
        result.visibility = .encryptedHidden
        return result
    }

    /// 解密查看内容；只返回明文，不修改 snippet 本身或数据库。
    func reveal(_ snippet: Snippet) async throws -> String {
        guard let cipherContent = snippet.cipherContent else {
            throw SnippetEncryptionError.missingCipherContent
        }

        let keyManager = self.keyManager
        return try await biometricGate.authenticate(reason: String(localized: "查看加密内容需要验证身份")) { context in
            let dek = try keyManager.unwrapDEK(context: context)
            return try SnippetCipher.decrypt(cipherContent: cipherContent, using: dek)
        }
    }

    /// 解除加密隐藏，把内容还原为公开明文；调用方负责持久化。
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
