// 文件职责：定义从 EventKit 中拍平出来的单个日历模型，供设置列表展示与开关。
// 分层：Model；纯值类型 Sendable，不 import AppKit/SwiftUI。
import Foundation

/// 用户可以关闭的单个日历，从 EventKit 拍平而来，用于设置列表。
struct MeetingCalendar: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    /// 所属账号，使不同账号下同名的「Calendar」仍然可区分。
    let accountName: String
}
