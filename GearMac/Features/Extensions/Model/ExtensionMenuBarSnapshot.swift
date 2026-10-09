// 文件职责：以纯值形式保存菜单栏项最近一次稳定渲染的快照，使恢复该项时无需启动运行时。
// 分层：Model；可编解码的纯数据，不 import AppKit/SwiftUI。
import Foundation

/// 一次已稳定渲染的纯值快照，使恢复菜单栏项无需运行时。
struct ExtensionMenuBarSnapshot: Codable, Sendable, Equatable {
    /// 菜单栏项显示的标题。
    let title: String?
    /// 悬停提示文本。
    let tooltip: String?
    /// 序列化后的图标数据。
    let iconJSON: String?
    /// 是否带下拉菜单。
    let hasMenu: Bool
}
