import Foundation

/// 用显式 key + `String(format:)` 拼带参数的本地化文案。
/// 不用 `String(localized: "abc \(x)")` 插值语法，是因为那种写法的 Catalog key
/// 由编译器根据插值内容自动生成（格式不透明），手写 `Localizable.xcstrings` 时
/// 很容易对不上导致翻译悄悄不生效；显式 key + `%@`/`%d` 占位符是完全可控的。
func localizedFormat(_ key: String, _ args: CVarArg...) -> String {
    String(format: String(localized: String.LocalizationValue(key)), arguments: args)
}
