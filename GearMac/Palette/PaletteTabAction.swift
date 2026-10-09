// 文件职责：解析 Tab 键应前往的下一屏（启动器 / AI / 剪贴板三者构成环形轮转）。
// 分层：Model；纯枚举与解析函数，无副作用。
import Foundation

/// Tab 在读者直接打开的三种表面间轮转；子屏幕则退回启动器。
enum PaletteTabAction: Equatable {
    /// 携带已输入文本：两端用同一查询各自缩窄列表。
    case carryQuery(PaletteMode)
    /// 全新屏幕：chat 的输入框存有半写消息，不属于其他屏幕的搜索。
    case freshScreen(PaletteMode)
    /// 已输入文本即问题，因此 chat 直接打开在回答上而不是空编辑器。
    case ask

    /// 按当前模式与功能开关解析 Tab 的下一跳。
    static func resolve(mode: PaletteMode, aiEnabled: Bool, clipboardEnabled: Bool) -> Self {
        switch mode {
        // 关闭的站点退出轮转，因此 Tab 会跳过它而非打开空屏。
        case .launcher:
            if aiEnabled { return .ask }
            return clipboardEnabled ? .carryQuery(.clipboard) : .carryQuery(.launcher)
        case .ai:
            return clipboardEnabled ? .freshScreen(.clipboard) : .carryQuery(.launcher)
        case .clipboard: return .carryQuery(.launcher)
        default: return .carryQuery(.launcher)
        }
    }
}
