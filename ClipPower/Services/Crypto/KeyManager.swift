import Foundation
import CryptoKit
import LocalAuthentication
import Security

enum KeyManagerError: Error {
    case secureEnclaveUnavailable
    case keychainError(OSStatus)
    case corruptedKeyMaterial
}

/// 任何支持 ECDH 密钥协商的私钥（`SecureEnclave.P256.KeyAgreement.PrivateKey` 与
/// 软件版 `P256.KeyAgreement.PrivateKey` 都天然满足这个接口），用于让 wrap/unwrap
/// 的核心算法可以脱离真实 Secure Enclave 硬件进行单元测试。
protocol KeyAgreementPrivateKey {
    var publicKey: P256.KeyAgreement.PublicKey { get }
    func sharedSecretFromKeyAgreement(with publicKeyShare: P256.KeyAgreement.PublicKey) throws -> SharedSecret
}

extension P256.KeyAgreement.PrivateKey: KeyAgreementPrivateKey {}
extension SecureEnclave.P256.KeyAgreement.PrivateKey: KeyAgreementPrivateKey {}

/// 管理"加密隐藏"功能所需的数据加密密钥（DEK）。
/// DEK 用 Secure Enclave 密钥包裹后存 Keychain，从不以明文持久化；
/// 每次解包都会通过 SecAccessControl 要求一次系统级鉴权（Touch ID / 密码）。
final class KeyManager: Sendable {
    static let shared = KeyManager()
    static let currentKeyID = "sep-dek-v1"

    private let service = "com.clippower.app.encryption"
    private let sepKeyAccount = "sep-wrapping-key"
    private let wrappedDEKAccount = "wrapped-dek"

    func isEncryptionConfigured() -> Bool {
        (try? loadWrappedDEK()) != nil
    }

    /// 首次启用加密隐藏：生成 SEP 密钥 + DEK，把包裹后的 DEK 存入 Keychain。
    /// 会触发一次系统鉴权（因为 SEP 私钥的 SecAccessControl 要求）。
    func setupEncryptionIfNeeded(context: LAContext) throws {
        guard !isEncryptionConfigured() else { return }
        guard SecureEnclave.isAvailable else {
            throw KeyManagerError.secureEnclaveUnavailable
        }

        let accessControl = try Self.makeAccessControl()
        let sepPrivateKey = try SecureEnclave.P256.KeyAgreement.PrivateKey(
            accessControl: accessControl,
            authenticationContext: context
        )

        let dek = SymmetricKey(size: .bits256)
        let wrapped = try Self.wrap(dek: dek, using: sepPrivateKey)

        try storeSEPKeyDataRepresentation(sepPrivateKey.dataRepresentation)
        try storeWrappedDEK(wrapped)
    }

    /// 解包取得 DEK；会触发一次系统鉴权。
    func unwrapDEK(context: LAContext) throws -> SymmetricKey {
        guard let sepKeyData = try loadSEPKeyDataRepresentation(),
              let wrapped = try loadWrappedDEK() else {
            throw KeyManagerError.corruptedKeyMaterial
        }
        let sepPrivateKey = try SecureEnclave.P256.KeyAgreement.PrivateKey(
            dataRepresentation: sepKeyData,
            authenticationContext: context
        )
        return try Self.unwrap(wrappedDEK: wrapped, using: sepPrivateKey)
    }

    // MARK: - Wrap / unwrap DEK（ECDH + HKDF 派生 KEK，纯算法，可脱离硬件单元测试）

    static func wrap<K: KeyAgreementPrivateKey>(dek: SymmetricKey, using recipientKey: K) throws -> Data {
        let ephemeralPrivateKey = P256.KeyAgreement.PrivateKey()
        let sharedSecret = try ephemeralPrivateKey.sharedSecretFromKeyAgreement(with: recipientKey.publicKey)
        let kek = deriveKEK(from: sharedSecret)

        let dekData = dek.withUnsafeBytes { Data($0) }
        let sealedDEK = try AES.GCM.seal(dekData, using: kek)
        guard let combined = sealedDEK.combined else {
            throw KeyManagerError.corruptedKeyMaterial
        }

        let ephemeralPublicKeyData = ephemeralPrivateKey.publicKey.rawRepresentation
        var payload = Data()
        payload.append(UInt8(ephemeralPublicKeyData.count))
        payload.append(ephemeralPublicKeyData)
        payload.append(combined)
        return payload
    }

    static func unwrap<K: KeyAgreementPrivateKey>(wrappedDEK: Data, using recipientKey: K) throws -> SymmetricKey {
        let headerSize = 1
        guard let lengthByte = wrappedDEK.first else {
            throw KeyManagerError.corruptedKeyMaterial
        }
        let publicKeyLength = Int(lengthByte)
        guard wrappedDEK.count > headerSize + publicKeyLength else {
            throw KeyManagerError.corruptedKeyMaterial
        }

        let start = wrappedDEK.startIndex
        let ephemeralPublicKeyData = wrappedDEK.subdata(
            in: (start + headerSize)..<(start + headerSize + publicKeyLength)
        )
        let sealedCombined = wrappedDEK.subdata(
            in: (start + headerSize + publicKeyLength)..<wrappedDEK.endIndex
        )

        let ephemeralPublicKey = try P256.KeyAgreement.PublicKey(rawRepresentation: ephemeralPublicKeyData)
        let sharedSecret = try recipientKey.sharedSecretFromKeyAgreement(with: ephemeralPublicKey)
        let kek = deriveKEK(from: sharedSecret)

        let sealedBox = try AES.GCM.SealedBox(combined: sealedCombined)
        let dekData = try AES.GCM.open(sealedBox, using: kek)
        return SymmetricKey(data: dekData)
    }

    private static func deriveKEK(from sharedSecret: SharedSecret) -> SymmetricKey {
        sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: Data("ClipPower-DEK-Wrap".utf8),
            outputByteCount: 32
        )
    }

    // MARK: - Keychain 存取

    private static func makeAccessControl() throws -> SecAccessControl {
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            [.privateKeyUsage, .userPresence],
            &error
        ) else {
            throw KeyManagerError.corruptedKeyMaterial
        }
        return access
    }

    private func storeSEPKeyDataRepresentation(_ data: Data) throws {
        let query = keychainQuery(account: sepKeyAccount)
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeyManagerError.keychainError(status)
        }
    }

    private func loadSEPKeyDataRepresentation() throws -> Data? {
        var query = keychainQuery(account: sepKeyAccount)
        query[kSecReturnData as String] = true

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeyManagerError.keychainError(status)
        }
        return data
    }

    private func storeWrappedDEK(_ data: Data) throws {
        let query = keychainQuery(account: wrappedDEKAccount)
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeyManagerError.keychainError(status)
        }
    }

    private func loadWrappedDEK() throws -> Data? {
        var query = keychainQuery(account: wrappedDEKAccount)
        query[kSecReturnData as String] = true

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeyManagerError.keychainError(status)
        }
        return data
    }

    private func keychainQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
