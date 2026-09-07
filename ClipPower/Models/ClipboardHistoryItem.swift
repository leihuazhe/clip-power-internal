import Foundation
import GRDB

struct ClipboardHistoryItem: Identifiable, Codable, Sendable, Equatable {
    var id: String
    var content: String
    var createdAt: Date

    init(id: String = UUID().uuidString, content: String, createdAt: Date = Date()) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
    }
}

extension ClipboardHistoryItem: FetchableRecord, PersistableRecord {
    static let databaseTableName = "clipboardHistoryItem"
}
