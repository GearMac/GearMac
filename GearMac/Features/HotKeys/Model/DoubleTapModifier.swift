// 文件职责：定义可绑定双击手势的四个修饰键（Control / Option / Shift / Command）及其图标与键帽表示。
// 分层：Model；纯枚举。
import Foundation

/// 可绑定双击手势的四个修饰键；Caps Lock 归属于 Hyper Key。
enum DoubleTapModifier: String, CaseIterable, Codable, Sendable {
    case control
    case option
    case shift
    case command

    /// 该修饰键的符号图标。
    var glyph: String {
        switch self {
        case .control: "⌃"
        case .option: "⌥"
        case .shift: "⇧"
        case .command: "⌘"
        }
    }

    /// 由两个相同图标组成的键帽序列（表示双击）。
    var keycaps: [String] { [glyph, glyph] }
}
