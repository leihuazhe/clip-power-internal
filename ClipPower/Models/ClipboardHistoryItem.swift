import Foundation
import GRDB

enum ClipboardContentKind: String, Codable, Sendable, Equatable {
    case text
    case image
    case file
}

struct ClipboardHistoryItem: Identifiable, Codable, Sendable, Equatable {
    var id: String
    var kind: ClipboardContentKind
    var textContent: String?
    var imageData: Data?
    var imageWidth: Int?
    var imageHeight: Int?
    var fileURLs: [String]
    var byteSize: Int?
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        kind: ClipboardContentKind,
        textContent: String? = nil,
        imageData: Data? = nil,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil,
        fileURLs: [String] = [],
        byteSize: Int? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.textContent = textContent
        self.imageData = imageData
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.fileURLs = fileURLs
        self.byteSize = byteSize
        self.createdAt = createdAt
    }

    /// 列表行/搜索里用的简短文字描述。
    var displayTitle: String {
        switch kind {
        case .text:
            return textContent ?? ""
        case .image:
            if let imageWidth, let imageHeight {
                return localizedFormat("imageDimensionsFormat", imageWidth, imageHeight)
            }
            return String(localized: "图片")
        case .file:
            if fileURLs.count > 1 {
                return localizedFormat("fileCountFormat", fileURLs.count)
            }
            return fileURLs.first.map { URL(fileURLWithPath: $0).lastPathComponent } ?? String(localized: "文件")
        }
    }
}

extension ClipboardHistoryItem: FetchableRecord, PersistableRecord {
    static let databaseTableName = "clipboardHistoryItem"
}
