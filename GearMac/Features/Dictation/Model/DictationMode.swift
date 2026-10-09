// 文件职责：定义听写的触发方式（按住说话或按一下切换）。
// 分层：Model/纯枚举；不执行副作用。
import Foundation

/// 听写触发模式。
enum DictationMode: String, CaseIterable, Identifiable, Sendable {
    case pushToTalk
    case toggle

    var id: Self { self }
    /// 设置界面中的显示标题。
    func title(_ language: AppLanguage) -> String {
        L10n.string(
            self == .pushToTalk ? DictationKey.modePushToTalk : DictationKey.modeToggle,
            language: language)
    }
}
