// 文件职责：定义 Escape 键行为偏好（逐级返回或直接关窗弹回根界面）。
// 分层：Settings（Model）；供设置界面与面板的按键处理共同读取的纯枚举。
import Foundation

/// 当本可被清空的搜索框已经为空时，Escape 在面板上的行为。
enum EscapeKeyBehavior: String, CaseIterable, Identifiable, Sendable {
    case navigateBackOrClose
    case closeAndPopToRoot

    var id: String { rawValue }

    /// 设置界面中展示的名称。
    var title: String {
        switch self {
        case .navigateBackOrClose: return "Navigate back or close window"
        case .closeAndPopToRoot: return "Close window and pop to root"
        }
    }
}
