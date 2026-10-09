// 文件职责：定义详情页专有的会议数据（位置、备注、参与者）及其从 HTML 备注提取纯文本、排序参与者的逻辑。
// 分层：Model；纯值类型 Equatable/Sendable，不 import AppKit/SwiftUI。
import Foundation

/// 仅详情页需要展示的数据，按需读取，以保持议程快照足够小。
struct MeetingDetails: Equatable, Sendable {
    let meetingID: MeetingEvent.ID
    let location: String?
    let notes: String?
    let attendees: [Attendee]

    /// 构造时清洗位置与备注（空白置空、HTML 转纯文本），并把组织者排在参与者之前。
    init(meetingID: MeetingEvent.ID, location: String?, notes: String?, attendees: [Attendee]) {
        self.meetingID = meetingID
        self.location = location.flatMap(Self.nonBlank)
        self.notes = notes.flatMap(Self.plainText(fromNotes:))
        self.attendees = attendees.filter(\.isOrganizer) + attendees.filter { !$0.isOrganizer }
    }

    /// 有些服务器把描述存为 HTML；详情页只展示其文本，从不展示标记。
    static func plainText(fromNotes notes: String) -> String? {
        guard notes.contains(/(?i)<\/?(?:a|b|i|u|p|br|div|span|strong|em|ul|ol|li)\b[^>]*>/)
        else { return nonBlank(notes) }
        let text =
            notes
            .replacing(/(?i)(?:<br\s*\/?>|<\/(?:p|div|li)>)/, with: "\n")
            .replacing(/(?i)<li\b[^>]*>/, with: "• ")
            .replacing(/<[^>]+>/, with: "")
            .replacing("&nbsp;", with: " ")
            .replacing("&lt;", with: "<")
            .replacing("&gt;", with: ">")
            .replacing("&quot;", with: "\"")
            .replacing("&#39;", with: "'")
            .replacing("&amp;", with: "&")
            .replacing(/\n{3,}/, with: "\n\n")
        return nonBlank(text)
    }

    /// 去除首尾空白，内容为空时返回 nil。
    private static func nonBlank(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension MeetingDetails {
    /// 单个参与者及其回复状态。
    struct Attendee: Hashable, Sendable {
        /// 参与者的回复状态。
        enum Response: Sendable {
            case accepted
            case tentative
            case declined
            case pending
        }

        let name: String
        let response: Response
        let isOrganizer: Bool
    }
}
