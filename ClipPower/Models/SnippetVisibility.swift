import Foundation

enum SnippetVisibility: String, Codable, CaseIterable, Sendable, Hashable {
    case normal
    case softHidden
    case encryptedHidden

    var displayName: String {
        switch self {
        case .normal: return String(localized: "公开")
        case .softHidden: return String(localized: "软隐藏")
        case .encryptedHidden: return String(localized: "加密隐藏")
        }
    }
}
