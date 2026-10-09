// 文件职责：定义布局条目目标屏幕的显示标识，用 UUID 与名称描述一块显示器。
// 分层：Model；保持纯净，仅依赖 Foundation 编解码，不 import AppKit/SwiftUI。
import Foundation

/// 条目目标的是哪块屏幕；以稳定标识记录，使其能经受重启与显示器重连。
struct WindowLayoutDisplay: Codable, Hashable, Sendable {
    /// 由服务层把 `CGDisplayCreateUUIDFromDisplayID` 的结果转成字符串，本文件从不读取它。
    var uuid: String
    /// 编写时记录的 `NSScreen.localizedName`，这样显示器缺席时仍能显示自己的名字。
    var name: String

    init(uuid: String, name: String) {
        self.uuid = uuid
        self.name = name
    }

    private enum CodingKeys: String, CodingKey {
        case uuid, name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uuid = try container.decode(String.self, forKey: .uuid)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Display"
    }
}
