import Foundation
import CryptoKit

enum SnippetCipherError: Error {
    case encodingFailed
}

/// 纯 AES-GCM 加解密；不涉及密钥来源，DEK 由 KeyManager 提供。
struct SnippetCipher {
    static func encrypt(plaintext: String, using key: SymmetricKey) throws -> Data {
        guard var data = plaintext.data(using: .utf8) else {
            throw SnippetCipherError.encodingFailed
        }
        defer { data.resetBytes(in: 0..<data.count) }

        let sealedBox = try AES.GCM.seal(data, using: key)
        guard let combined = sealedBox.combined else {
            throw SnippetCipherError.encodingFailed
        }
        return combined
    }

    static func decrypt(cipherContent: Data, using key: SymmetricKey) throws -> String {
        let sealedBox = try AES.GCM.SealedBox(combined: cipherContent)
        var data = try AES.GCM.open(sealedBox, using: key)
        defer { data.resetBytes(in: 0..<data.count) }

        guard let text = String(data: data, encoding: .utf8) else {
            throw SnippetCipherError.encodingFailed
        }
        return text
    }
}
