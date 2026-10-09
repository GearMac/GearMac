// 文件职责：为敏感值（如邮箱地址）生成稳定且每次一致的乱码替身，供脱敏展示使用。
// 分层：Service（纯逻辑工具）；确定性替换，不依赖 UI、IO 或任何全局状态。
import Foundation

/// 字符替换本身就是脱敏，模糊只是提示手段；值的长度依然会泄露。
enum RedactedPlaceholder {
    /// 不含 `i`、`l`、`o`、`0`、`1`：半模糊的字形不应能被排除法辨认出来。
    private static let alphabet = Array("abcdefghjkmnpqrstuvwxyz23456789")

    /// 保留这些字符：它们体现地址的结构而非内容。
    private static let structural: Set<Character> = ["@", ".", "-", "_"]

    /// 相同输入始终得到相同替身。
    static func forValue(_ value: String) -> String {
        var state = seed(value)
        return String(
            value.map { character in
                guard !structural.contains(character) else { return character }
                return alphabet[Int(next(&state) % UInt32(alphabet.count))]
            })
    }

    /// 对值的 UTF-8 字节做 FNV-1a 哈希——开销低、跨进程启动稳定，且不构成任何安全边界。
    private static func seed(_ value: String) -> UInt32 {
        var state: UInt32 = 0x811c_9dc5
        for byte in value.utf8 {
            state ^= UInt32(byte)
            state = state &* 0x0100_0193
        }
        return state
    }

    /// 一次 xorshift-multiply 轮运算，避免相邻字符呈现出可见的规律。
    private static func next(_ state: inout UInt32) -> UInt32 {
        state ^= state >> 13
        state = state &* 0x85eb_ca6b
        state ^= state >> 16
        state = state &* 0xc2b2_ae35
        return state
    }
}
