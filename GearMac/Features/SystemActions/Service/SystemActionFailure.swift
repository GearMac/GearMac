// 文件职责：系统动作失败的错误类型，携带面向用户的文案与需要引导前往的系统设置类别。
// 分层：Model/Service 边界；实现 LocalizedError，供上层统一弹窗与跳转设置。
import Foundation

/// 系统动作执行失败：message 面向用户，settings 指出需要打开的系统设置面板。
struct SystemActionFailure: LocalizedError, Sendable {
    /// 失败涉及的系统设置类别，决定错误弹窗的跳转目标。
    enum Settings: Sendable {
        case accessibility
        case automation
        case bluetooth
    }

    /// 失败文案的来源：可本地化的键，或来自系统/子进程的运行时文本。
    enum Message: Sendable {
        /// 本地化键，可携带一个 `String(format:)` 占位参数（如错误码）。
        case key(SystemActionsKey, argument: String?)
        /// 无法预定义文案的运行时文本（如子进程 stderr）。
        case text(String)
    }

    let message: Message
    let settings: Settings?

    /// 由本地化键构造，可选携带一个占位参数。
    init(_ key: SystemActionsKey, argument: String? = nil, settings: Settings? = nil) {
        message = .key(key, argument: argument)
        self.settings = settings
    }

    /// 由运行时文本构造（无法本地化，保留原文）。
    init(text: String, settings: Settings? = nil) {
        message = .text(text)
        self.settings = settings
    }

    /// 按指定语言解析面向用户的失败文案。
    func localizedMessage(_ language: AppLanguage) -> String {
        switch message {
        case .text(let value):
            return value
        case .key(let key, let argument):
            let format = L10n.string(key, language: language)
            guard let argument else { return format }
            return String(format: format, argument)
        }
    }

    var errorDescription: String? { localizedMessage(.english) }
}
