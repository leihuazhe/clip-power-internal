import Foundation

enum SnippetVisibility: String, Codable, CaseIterable, Sendable, Hashable {
    case normal
    case softHidden
    case encryptedHidden

    var displayName: String {
        switch self {
        case .normal: return "公开"
        case .softHidden: return "软隐藏"
        case .encryptedHidden: return "加密隐藏"
        }
    }
}
