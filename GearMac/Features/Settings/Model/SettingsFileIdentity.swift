// 文件职责：为 settings.json 中缺少身份标识的记录生成稳定 UUID（由文本的 SHA-256 派生）。
// 分层：Model；同一段文本永远得到同一个 UUID，不依赖调用时机。
import CryptoKit
import Foundation

/// 文件未提供的身份标识：以派生方式生成，使同一段文本的每次读取结果一致。
enum SettingsFileIdentity {
    /// 由 SHA-256 派生出的 version 8 UUID，因此手工写入的记录在多次重载后保持同一个 id。
    static func uuid(for text: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(text.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x80
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
            ))
    }
}
