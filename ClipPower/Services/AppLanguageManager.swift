import Foundation
import AppKit

/// 管理"App 显示语言"这个跟系统语言无关的独立偏好。
///
/// macOS 对本地化字符串的解析（`Bundle.main` 用哪套语言的 .xcstrings 翻译）是进程
/// 启动早期就定死并缓存的，运行时改 `UserDefaults` 的 `AppleLanguages` 键不会让
/// 已经在跑的进程里的文案立刻刷新——所以语言切换统一走"写偏好 + 重新拉起同一个
/// App 进程"，不做零重启的实时切换（那需要给全部文案单独写一套自定义查表函数，
/// 对这个个人小工具来说复杂度和收益不成比例）。
enum AppLanguageManager {
    private static let preferenceKey = "ClipPower.appLanguage"

    /// `ClipPowerTests`把 `ClipPower.app` 本身当 test host 跑（`applicationDidFinishLaunching`
    /// 在跑单测时真的会执行一次），首次启动的静默重启逻辑在这个上下文里毫无意义——
    /// 重启一个新进程不会让等待中的 XCTest 驱动进程收到任何东西，`terminate` 反而会
    /// 直接杀掉测试宿主进程，表现就是 `xcodebuild test` 报"测试运行器过早退出"。
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// 区分"真正的首次启动"（还没存过偏好）和"已经选过语言"。
    static var hasStoredPreference: Bool {
        UserDefaults.standard.string(forKey: preferenceKey) != nil
    }

    static var current: AppLanguage {
        if let raw = UserDefaults.standard.string(forKey: preferenceKey), let language = AppLanguage(rawValue: raw) {
            return language
        }
        return .en
    }

    /// 只负责落盘偏好 + 系统 `AppleLanguages`，不做任何重启动作——
    /// 调用方（首次启动 / 设置页切换）各自决定要不要立刻重启。
    static func apply(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: preferenceKey)
        UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
    }

    /// 重新拉起同一个 .app bundle 的新进程，再退出当前进程——让 `Bundle.main`
    /// 在新进程里从头按新语言解析本地化字符串。
    ///
    /// `openApplication` 是异步的（底层是一次到 Launch Services 的 XPC 往返），
    /// 如果发出请求后立刻 `terminate`，当前进程可能在这次 XPC 往返完成之前就
    /// 已经退出，导致这次拉起请求直接被丢弃——实测过，`terminate` 必须放在
    /// completion handler 里等这次请求真正处理完之后再调用。
    static func relaunch() {
        let url = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }
}
