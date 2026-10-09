// 文件职责：从 Detail markdown 图片的 URL 查询参数（`?raycast-width=` / `?raycast-height=`）解析出期望的宽高尺寸。
// 分层：Model；纯 URL 解析，不 import AppKit/SwiftUI。
import Foundation

/// Detail markdown 图片通过 `?raycast-width=` / `?raycast-height=` 请求的尺寸。
struct ExtensionImageSize: Equatable {
    let width: Double?
    let height: Double?

    /// 当 URL 既未指定宽也未指定高时返回 nil，使无提示的图片保持默认框架。
    init?(url: URL) {
        let text = url.absoluteString
        // 内联（data:）负载本身可能带有 `?`，因此它的查询串从逗号之后才开始。
        let start = url.scheme == "data" ? text.firstIndex(of: ",") ?? text.endIndex : text.startIndex
        guard let mark = text[start...].firstIndex(of: "?") else { return nil }
        var values: [String: Double] = [:]
        for pair in text[text.index(after: mark)...].split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, let value = Double(parts[1]), value.isFinite, value > 0
            else { continue }
            values[String(parts[0])] = value
        }
        self.init(width: values["raycast-width"], height: values["raycast-height"])
        if width == nil && height == nil { return nil }
    }

    /// 用已解析好的宽高构造实例。
    init(width: Double?, height: Double?) {
        self.width = width
        self.height = height
    }
}
