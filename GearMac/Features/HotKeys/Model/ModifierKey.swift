// 文件职责：枚举左右两侧的具体修饰键与 Globe 键，提供对应关系、键帽与设备掩码，并据此判定当前按下的键集合。
// 分层：Model；纯值类型。
import Foundation

/// 左侧或右侧的具体修饰键，以及 Globe 键。
enum ModifierKey: String, CaseIterable, Codable, Sendable {
    case leftControl, rightControl
    case leftOption, rightOption
    case leftShift, rightShift
    case leftCommand, rightCommand
    case globe

    /// 该键对应的通用双击修饰键类型（Globe 为 nil）。
    var modifier: DoubleTapModifier? {
        switch self {
        case .leftControl, .rightControl: .control
        case .leftOption, .rightOption: .option
        case .leftShift, .rightShift: .shift
        case .leftCommand, .rightCommand: .command
        case .globe: nil
        }
    }

    /// 左/右侧别字符串（Globe 为 nil）。
    var side: String? {
        switch self {
        case .leftControl, .leftOption, .leftShift, .leftCommand: "Left"
        case .rightControl, .rightOption, .rightShift, .rightCommand: "Right"
        case .globe: nil
        }
    }

    /// 展示用的键帽序列（侧别加修饰符图标）。
    var keycaps: [String] { (side.map { [$0] } ?? []) + [modifier?.glyph ?? "🌐︎"] }

    /// 单击该键对应的绑定。
    var singleBinding: HotKeyBinding { self == .globe ? .globe : .modifier(self) }
    /// 双击该键对应的绑定。
    var doubleBinding: HotKeyBinding { self == .globe ? .doubleGlobe : .doubleModifier(self) }

    // 设备掩码可在共享的通用修饰位仍保持置位时区分左右两个键。
    private var deviceMask: UInt64 {
        switch self {
        case .leftControl: 0x0001
        case .rightControl: 0x2000
        case .leftOption: 0x0020
        case .rightOption: 0x0040
        case .leftShift: 0x0002
        case .rightShift: 0x0004
        case .leftCommand: 0x0008
        case .rightCommand: 0x0010
        case .globe: 0
        }
    }

    /// 从事件标志位与 Globe 按下状态得出当前按住的修饰键集合。
    static func held(in flags: UInt64, globeDown: Bool) -> Set<Self> {
        var held = Set(allCases.filter { $0.deviceMask & flags != 0 })
        if globeDown { held.insert(.globe) }
        return held
    }
}
