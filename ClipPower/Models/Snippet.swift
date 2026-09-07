import Foundation
import GRDB

/// 领域模型；`id` 直接存储 UUID 字符串，与 `snippet` 表的 TEXT 主键一一对应。
struct Snippet: Identifiable, Codable, Sendable, Equatable {
    var id: String
    var name: String
    var keyword: String?
    var contentType: SnippetContentType
    var plainContent: String?
    var cipherContent: Data?
    var keyID: String?
    var visibility: SnippetVisibility
    var tags: [String]
    var usageCount: Int
    var lastUsedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
    var deletedAt: Date?

    init(
        id: String = UUID().uuidString,
        name: String,
        keyword: String? = nil,
        contentType: SnippetContentType = .plainText,
        plainContent: String? = nil,
        cipherContent: Data? = nil,
        keyID: String? = nil,
        visibility: SnippetVisibility = .normal,
        tags: [String] = [],
        usageCount: Int = 0,
        lastUsedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isDeleted: Bool = false,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.keyword = keyword
        self.contentType = contentType
        self.plainContent = plainContent
        self.cipherContent = cipherContent
        self.keyID = keyID
        self.visibility = visibility
        self.tags = tags
        self.usageCount = usageCount
        self.lastUsedAt = lastUsedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
        self.deletedAt = deletedAt
    }
}

extension Snippet: FetchableRecord, PersistableRecord {
    static let databaseTableName = "snippet"
}
