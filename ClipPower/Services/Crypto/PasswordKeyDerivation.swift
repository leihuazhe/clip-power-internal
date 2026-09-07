import Foundation
import CryptoKit
import CommonCrypto

/// 导出/导入密码派生密钥（PBKDF2-SHA256），只用于跨设备迁移加密隐藏内容，
/// 派生结果不持久化，只在一次导出/导入流程内的内存中使用。
enum PasswordKeyDerivation {
    static func deriveKey(password: String, salt: Data, iterations: Int = 200_000, keyLength: Int = 32) -> SymmetricKey {
        var derivedKeyData = Data(count: keyLength)
        let passwordData = Data(password.utf8)

        derivedKeyData.withUnsafeMutableBytes { derivedKeyBytes in
            salt.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { passwordBytes in
                    _ = CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.bindMemory(to: UInt8.self).baseAddress,
                        passwordData.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedKeyBytes.bindMemory(to: UInt8.self).baseAddress,
                        keyLength
                    )
                }
            }
        }
        return SymmetricKey(data: derivedKeyData)
    }

    static func randomSalt(length: Int = 16) -> Data {
        Data((0..<length).map { _ in UInt8.random(in: 0...255) })
    }
}
