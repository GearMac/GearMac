// 文件职责：滑块与音量条背后的实时音量状态，作为可观察对象发布，使重复调节能原地刷新。
// 分层：Service/UI 状态；仅承载数值，不执行 CoreAudio 操作。
import Foundation

/// 滑块与音量条背后的实时音量，作为可观察对象发布，使重复调节能原地刷新。
@Observable
final class VolumeState {
    var level: Double
    var muted: Bool

    init(level: Double, muted: Bool = false) {
        self.level = level
        self.muted = muted
    }
}
