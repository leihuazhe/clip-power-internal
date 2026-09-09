import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case en
    case zhHans = "zh-Hans"
    case ja

    var id: String { rawValue }

    /// 每种语言的名字永远用它自己的写法显示，不跟随当前 App 语言本地化——
    /// 不管界面现在是什么语言，用户都能在列表里认出自己想切换到的那个，
    /// 这是几乎所有 App 语言选择器的标准做法。
    var displayName: String {
        switch self {
        case .en: return "English"
        case .zhHans: return "简体中文"
        case .ja: return "日本語"
        }
    }
}
