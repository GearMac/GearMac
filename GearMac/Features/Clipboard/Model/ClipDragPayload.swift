// 文件职责：定义剪贴板行被拖拽时交给目标 App 的载荷类型，并把 ClipboardItem 映射成该载荷。
// 分层：Model；保持纯净，不得 import AppKit/SwiftUI，不产生副作用。
import Foundation

/// 一行内容拖拽到目标 App 时交给对方的东西。
enum ClipDragPayload: Equatable, Sendable {
    case file(URL)
    /// 浏览器读取 `public.url`，文本框读取字符串，因此两种表示都要带上。
    case link(URL, String)
    case text(String)
}

extension ClipboardItem {
    /// 链接判定始终以 `textForm` 为唯一答案，使拖拽与类型筛选不会出现分歧。
    var dragPayload: ClipDragPayload {
        if let path = imagePath ?? filePath { return .file(URL(fileURLWithPath: path)) }
        let copy = text ?? ""
        guard textForm == .link else { return .text(copy) }
        switch QuicklinkDestination.detect(copy) {
        case .web(let url), .network(let url), .deeplink(let url): return .link(url, copy)
        case .path, nil: return .text(copy)
        }
    }
}
