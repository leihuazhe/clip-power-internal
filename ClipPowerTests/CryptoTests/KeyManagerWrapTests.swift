import XCTest
import CryptoKit
@testable import ClipPower

/// 只测试 wrap/unwrap 的 ECDH + HKDF + AES-GCM 算法本身，用软件 P256 密钥代替
/// 真实 Secure Enclave（真实 SEP 路径依赖 Touch ID 系统弹窗，无法在无 GUI 环境自动化，
/// 需要手动集成验证，见 docs/design.md 的验证方式一节）。
final class KeyManagerWrapTests: XCTestCase {
    func testWrapUnwrapRoundTrip() throws {
        let recipientKey = P256.KeyAgreement.PrivateKey()
        let dek = SymmetricKey(size: .bits256)

        let wrapped = try KeyManager.wrap(dek: dek, using: recipientKey)
        let unwrapped = try KeyManager.unwrap(wrappedDEK: wrapped, using: recipientKey)

        XCTAssertEqual(dek.withUnsafeBytes { Data($0) }, unwrapped.withUnsafeBytes { Data($0) })
    }

    func testUnwrapFailsWithWrongRecipientKey() throws {
        let recipientKey = P256.KeyAgreement.PrivateKey()
        let wrongKey = P256.KeyAgreement.PrivateKey()
        let dek = SymmetricKey(size: .bits256)

        let wrapped = try KeyManager.wrap(dek: dek, using: recipientKey)

        XCTAssertThrowsError(try KeyManager.unwrap(wrappedDEK: wrapped, using: wrongKey))
    }

    func testWrapProducesDifferentPayloadEachTime() throws {
        let recipientKey = P256.KeyAgreement.PrivateKey()
        let dek = SymmetricKey(size: .bits256)

        let first = try KeyManager.wrap(dek: dek, using: recipientKey)
        let second = try KeyManager.wrap(dek: dek, using: recipientKey)

        XCTAssertNotEqual(first, second, "每次 wrap 都应使用新的临时密钥，密文不应重复")
    }

    func testUnwrapFailsOnCorruptedPayload() throws {
        let recipientKey = P256.KeyAgreement.PrivateKey()
        let dek = SymmetricKey(size: .bits256)
        var wrapped = try KeyManager.wrap(dek: dek, using: recipientKey)
        wrapped[wrapped.count - 1] ^= 0xFF

        XCTAssertThrowsError(try KeyManager.unwrap(wrappedDEK: wrapped, using: recipientKey))
    }
}
