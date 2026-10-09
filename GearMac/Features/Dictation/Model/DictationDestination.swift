// 文件职责：定义听写结果的输出方式（粘贴、复制或两者）。
// 分层：Model/纯枚举；只描述选项与能力，不执行任何副作用。
import Foundation

/// 听写完成后的交付方式。
enum DictationDestination: String, CaseIterable, Identifiable, Sendable {
    case paste
    case copy
    case both

    var id: Self { self }
    /// 用于设置界面的显示标题。
    func title(_ language: AppLanguage) -> String {
        let key: DictationKey
        switch self {
        case .paste: key = .destinationPaste
        case .copy: key = .destinationCopy
        case .both: key = .destinationBoth
        }
        return L10n.string(key, language: language)
    }

    /// 是否执行粘贴。
    var pastes: Bool { self != .copy }
    /// 是否复制到剪贴板。
    var copies: Bool { self != .paste }
}
