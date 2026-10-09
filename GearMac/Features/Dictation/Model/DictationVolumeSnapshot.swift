// 文件职责：记录听写期间系统输出音量被压低前的状态，用于崩溃后恢复。
// 分层：Model/可持久化值类型；不含硬件访问。
import Foundation

/// 输出音量快照：记录设备、原始音量与最近写入值，可在重启后恢复。
struct DictationVolumeSnapshot: Codable, Sendable {
    let deviceUID: String
    let original: Float
    var lastSet: Float
    var previous: Float?

    /// 校验设备标识与各音量值是否落在合法范围。
    var isValid: Bool {
        !deviceUID.isEmpty && (0...1).contains(original) && (0...1).contains(lastSet)
            && previous.map { (0...1).contains($0) } != false
    }

    /// 判断给定音量是否与最近写入值或上一值一致（用于防御外部改动）。
    func matches(_ volume: Float) -> Bool {
        isValid
            && (abs(volume - lastSet) < 0.01
                || previous.map { abs(volume - $0) < 0.01 } == true)
    }
}
