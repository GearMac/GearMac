// 文件职责：把长音频按最大长度切分为多个采样区间，切点尽量落在静音处。
// 分层：Model/纯函数；仅做区间计算，不修改输入。
import Foundation

/// 音频分块工具：为超出模型窗口的录音计算切分区间。
enum DictationAudioChunks {
    /// 返回不超过 maximum 长度的连续区间，并在末尾附近寻找最低能量点作为切点。
    static func ranges(in samples: [Float], maximum: Int) -> [Range<Int>] {
        precondition(maximum > 0)
        var ranges = [Range<Int>]()
        var start = 0
        while start < samples.count {
            var end = min(start + maximum, samples.count)
            if end < samples.count, end - start >= 3200 {
                let window = 3200
                var quietest: Float = .infinity
                for offset in stride(from: max(start, end - 48_000), through: end - window, by: 160) {
                    let energy = samples[offset..<(offset + window)].reduce(Float.zero) { $0 + $1 * $1 }
                    if energy <= quietest { quietest = energy; end = offset + window / 2 }
                }
            }
            ranges.append(start..<end)
            start = end
        }
        return ranges
    }
}
