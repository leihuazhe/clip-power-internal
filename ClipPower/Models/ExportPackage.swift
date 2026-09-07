import Foundation

struct ExportKDFInfo: Codable, Sendable {
    var algorithm: String
    var salt: Data
    var iterations: Int
}

struct ExportedSnippet: Codable, Sendable {
    var id: String
    var name: String
    var keyword: String?
    var contentType: SnippetContentType
    var visibility: SnippetVisibility
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date

    /// normal / softHidden 直接存明文。
    var content: String?

    /// encryptedHidden 且未设置导出密码：原样导出设备绑定密文，只有回到同一台机器才可能解开。
    var deviceBoundCipherContent: Data?

    /// encryptedHidden 且设置了导出密码：用导出密码派生的临时密钥重新加密，可跨设备迁移。
    var passwordProtectedCipherContent: Data?
}

struct ExportPackage: Codable, Sendable {
    var formatVersion: Int
    var exportedAt: Date
    var requiresExportPassword: Bool
    var exportKDF: ExportKDFInfo?
    var snippets: [ExportedSnippet]
}
