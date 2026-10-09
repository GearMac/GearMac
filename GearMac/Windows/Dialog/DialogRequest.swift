// 文件职责：对话框的数据模型：按钮、语气、请求描述以及可选的附件控件。
// 分层：Model；纯值类型，不依赖 AppKit/SwiftUI。
import Foundation

/// 对话框中的一个按钮；role 决定其配色，严重程度另行由 `DialogTone` 表达。
struct DialogAction {
    /// 按钮角色，决定其样式与语义。
    enum Role {
        case standard
        case destructive
        case cancel
    }

    let title: String
    var role: Role = .standard
}

/// 对话框的严重程度；它只给图标着色，不决定用哪个图标。见 docs/ui.md。
enum DialogTone: Sendable {
    case neutral
    case success
    case danger
}

/// 一次对话框呈现的完整描述。
struct DialogRequest {
    let title: String
    var message: String?
    /// 当标题已点明主题、图标只会重复信息时为 nil。
    let symbol: String?
    var tone: DialogTone = .neutral
    var actions: [DialogAction]
    /// ↵ 触发的按钮索引，通常是主操作。
    var defaultIndex: Int
    /// 未做选择就关闭时采用的结果：按下 Esc 或失去 key 状态。
    var cancelIndex: Int
    /// 调用方从其传入的状态对象中读回结果。
    var accessory: DialogAccessory?
}

/// 对话框可携带的附件控件类型；一个对话框最多一个，因此各分支天然互斥。
enum DialogAccessory {
    case volume(VolumeState)
    case eventDraft(EventDraftState)
    case snippetArguments(SnippetArgumentsState)

    /// 决定 ←/→/↑/↓ 归属于该控件，而不是控件内部当前聚焦的元素。
    var claimsArrowKeys: Bool {
        if case .volume = self { return true }
        return false
    }
}
