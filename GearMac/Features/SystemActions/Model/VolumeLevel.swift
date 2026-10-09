// 文件职责：音量命令所用的档位网格，提供取整、步进、百分比与图标选择等纯计算。
// 分层：Model；纯函数，CoreAudio 的读写不在这里。
import Foundation

/// 音量命令移动所用的档位网格，以及音量值的呈现方式；CoreAudio 操作不在此处。
enum VolumeLevel {
    /// 20 档、每档 5%，使各档位都是整数百分比，预设值也正好落在网格上。
    static let steps = 20
    static let step = 1 / Double(steps)

    /// 把音量值限制到 0...1。
    static func clamped(_ level: Double) -> Double {
        min(max(level, 0), 1)
    }

    /// 移动到相邻的下一条网格线且不越过；已在网格上的值会移动完整一档。
    static func stepped(_ level: Double, up: Bool) -> Double {
        let exact = clamped(level) * Double(steps)
        // 该微小偏移用于吸收二进制误差，否则下调一档时可能原地不动。
        let line =
            up ? (exact + tolerance).rounded(.down) + 1 : (exact - tolerance).rounded(.up) - 1
        return clamped(line / Double(steps))
    }

    /// 把音量值格式化为整数百分比文本。
    static func percentage(_ level: Double) -> String {
        "\(Int((clamped(level) * 100).rounded()))%"
    }

    /// 由 HUD 和滑块共用，确保同一音量值不会画出两种图标。
    static func symbol(level: Double, muted: Bool = false) -> String {
        let level = clamped(level)
        if muted || level == 0 { return "speaker.slash.fill" }
        return level < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.2.fill"
    }

    private static let tolerance = 1e-6
}
