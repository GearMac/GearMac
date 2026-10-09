// 文件职责：Quick AI 打开时的落地策略：决定恢复最近对话还是开新对话，以及空闲多久后视为新对话。
// 分层：Model；只以时间戳为输入，不得 import AppKit/SwiftUI。
import Foundation

/// 唤起 Quick AI 时落在哪里；在打开时决定，而不是在面板隐藏时决定。
enum AIOpensTo: Int, CaseIterable, Identifiable, Sendable {
    case recent = 0
    case newConversation = 1

    var id: Int { rawValue }

    /// 设置界面中的选项名称。
    func title(_ language: AppLanguage) -> String {
        switch self {
        case .recent: return L10n.string(AIKey.opensToRecent, language: language)
        case .newConversation: return L10n.string(AIKey.opensToNew, language: language)
        }
    }
}

/// 以分钟为原始值；`never` 取负值，以免与未设置键读出的 0 冲突。
enum AINewChatAfter: Int, CaseIterable, Identifiable, Sendable {
    case twoMinutes = 2
    case fiveMinutes = 5
    case tenMinutes = 10
    case thirtyMinutes = 30
    case never = -1

    var id: Int { rawValue }

    /// 设置界面中的选项名称。
    func title(_ language: AppLanguage) -> String {
        self == .never
            ? L10n.string(AIKey.newAfterNever, language: language)
            : String(format: L10n.string(AIKey.newAfterMinutes, language: language), rawValue)
    }

    /// 该空闲阈值对应的秒数。
    var interval: TimeInterval { TimeInterval(rawValue) * 60 }
}

/// 以单个时间戳作为时钟，因此结论能跨重启存活，而隐藏计时器做不到。
enum AIConversationOpenPolicy {
    /// 打开时的结论：恢复上次对话，或开始新对话。
    enum Decision: Equatable, Sendable {
        case resume
        case startNew
    }

    /// 没有可回退的内容时 `lastActiveAt` 为 nil，这种情况本身就等同于开新对话。
    static func decide(
        opensTo: AIOpensTo, newAfter: AINewChatAfter, lastActiveAt: Date?, now: Date
    ) -> Decision {
        guard opensTo == .recent, let lastActiveAt else { return .startNew }
        guard newAfter != .never else { return .resume }
        // 时钟回拨会产生负的间隔；此时不能把读者困在旧对话里。
        let idle = now.timeIntervalSince(lastActiveAt)
        return idle >= newAfter.interval ? .startNew : .resume
    }
}
