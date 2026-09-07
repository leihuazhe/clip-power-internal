import XCTest
import CryptoKit
@testable import ClipPower

final class SnippetCipherTests: XCTestCase {
    func testEncryptDecryptRoundTrip() throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = "sk-super-secret-api-key-12345"

        let cipherContent = try SnippetCipher.encrypt(plaintext: plaintext, using: key)
        let decrypted = try SnippetCipher.decrypt(cipherContent: cipherContent, using: key)

        XCTAssertEqual(decrypted, plaintext)
    }

    func testEncryptProducesDifferentCiphertextEachTime() throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = "same plaintext"

        let first = try SnippetCipher.encrypt(plaintext: plaintext, using: key)
        let second = try SnippetCipher.encrypt(plaintext: plaintext, using: key)

        XCTAssertNotEqual(first, second, "每次加密应使用不同的随机 nonce")
    }

    func testDecryptFailsWithWrongKey() throws {
        let key = SymmetricKey(size: .bits256)
        let wrongKey = SymmetricKey(size: .bits256)
        let cipherContent = try SnippetCipher.encrypt(plaintext: "secret", using: key)

        XCTAssertThrowsError(try SnippetCipher.decrypt(cipherContent: cipherContent, using: wrongKey))
    }

    func testDecryptFailsWhenCiphertextTampered() throws {
        let key = SymmetricKey(size: .bits256)
        var cipherContent = try SnippetCipher.encrypt(plaintext: "secret", using: key)
        cipherContent[cipherContent.count - 1] ^= 0xFF

        XCTAssertThrowsError(try SnippetCipher.decrypt(cipherContent: cipherContent, using: key))
    }
}
