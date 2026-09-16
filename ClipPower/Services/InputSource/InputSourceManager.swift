import Foundation
import Carbon

/// 一个可选中的输入源（键盘布局或输入法），对应 TIS 的 `TISInputSource`。
struct InputSourceInfo: Identifiable, Equatable {
    /// TIS 的 `kTISPropertyInputSourceID`，如 `com.apple.inputmethod.SCIM.ITABC`。
    var id: String
    var localizedName: String
}

/// 封装 Carbon 的 Text Input Sources 服务（`TISCreateInputSourceList` / `TISSelectInputSource`），
/// 只处理"用户已在系统「键盘」设置里启用"的输入源——和系统自带的输入法切换一样，
/// 不能凭空选中一个没启用的输入法。
enum InputSourceManager {
    /// 当前用户已启用、且可以被程序选中的键盘输入源列表。
    static func listSelectable() -> [InputSourceInfo] {
        guard let sourceList = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }
        return sourceList.compactMap(makeInfo(from:))
    }

    /// 切换到指定 `inputSourceID` 对应的输入源；找不到（比如用户后来在系统设置里关掉了）
    /// 就什么都不做。
    static func select(inputSourceID: String) {
        guard let sourceList = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource],
              let target = sourceList.first(where: { stringProperty($0, kTISPropertyInputSourceID) == inputSourceID }) else {
            return
        }
        TISSelectInputSource(target)
    }

    private static func makeInfo(from source: TISInputSource) -> InputSourceInfo? {
        guard boolProperty(source, kTISPropertyInputSourceIsSelectCapable),
              let id = stringProperty(source, kTISPropertyInputSourceID),
              let name = stringProperty(source, kTISPropertyLocalizedName) else {
            return nil
        }
        return InputSourceInfo(id: id, localizedName: name)
    }

    private static func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }

    private static func boolProperty(_ source: TISInputSource, _ key: CFString) -> Bool {
        guard let raw = TISGetInputSourceProperty(source, key) else { return false }
        return Unmanaged<CFBoolean>.fromOpaque(raw).takeUnretainedValue() == kCFBooleanTrue
    }
}
