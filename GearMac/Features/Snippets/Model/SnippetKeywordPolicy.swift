// 文件职责：定义 snippet 关键词触发的纯逻辑——事件 tap 生命周期决策，以及按键缓冲区的最长后缀匹配。
// 分层：Model；纯状态机，不发起任何系统调用或副作用。
import Foundation

/// 关键词监听器对外暴露的状态。
enum SnippetKeywordListenerStatus: Equatable, Sendable {
    case off  // 未请求监听或已停止
    case needsAccessibility  // 已请求，但缺少辅助功能授权或事件 tap 尚未就绪
    case active  // 事件 tap 已安装并生效
}

/// 事件 tap 的存活状态策略：根据请求、会话、授权与 tap 现状推导下一步动作。
struct SnippetKeywordLifecyclePolicy: Sendable {
    /// 事件 tap 当前的存在状态。
    enum TapState: Equatable, Sendable {
        case absent  // 尚未安装
        case disabled  // 已安装但被系统禁用
        case active  // 已安装并处于启用状态
    }

    /// 本次决策要求对事件 tap 采取的动作。
    enum TapAction: Equatable, Sendable {
        case none  // 保持现状
        case install  // 安装事件 tap
        case reenable  // 重新启用被禁用的 tap
        case tearDown  // 拆除事件 tap
    }

    /// 生命周期决策结果：期望的对外状态与需要执行的 tap 动作。
    struct Decision: Equatable, Sendable {
        let status: SnippetKeywordListenerStatus
        let tapAction: TapAction
    }

    /// 根据「是否请求、会话是否活跃、是否有辅助功能授权、tap 现状」推导状态与动作。
    static func decide(
        isRequested: Bool,
        isSessionActive: Bool,
        hasAccessibility: Bool,
        tapState: TapState
    ) -> Decision {
        guard isRequested else {
            return Decision(
                status: .off,
                tapAction: tapState == .absent ? .none : .tearDown)
        }
        guard isSessionActive, hasAccessibility else {
            return Decision(
                status: .needsAccessibility,
                tapAction: tapState == .absent ? .none : .tearDown)
        }

        switch tapState {
        case .absent:
            return Decision(status: .needsAccessibility, tapAction: .install)
        case .disabled:
            return Decision(status: .needsAccessibility, tapAction: .reenable)
        case .active:
            return Decision(status: .active, tapAction: .none)
        }
    }
}

/// 关键词匹配策略：维护待匹配的关键词表与按键缓冲区，并产出命中结果。
struct SnippetKeywordPolicy: Sendable {
    /// 参与匹配的关键词（已小写化）及其对应的删除回退长度。
    struct Keyword: Equatable, Sendable {
        let snippetID: StoredSnippet.ID
        let value: String
        let deletionCount: Int

        /// 规范化关键词：去除首尾空白并小写化；`deletionCount` 为需要删除的触发文本长度。
        init(snippetID: StoredSnippet.ID, value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            self.snippetID = snippetID
            self.value = trimmed.lowercased()
            deletionCount = trimmed.count
        }
    }

    /// 一次关键词命中：snippet ID、命中的关键词与需要删除的字符数。
    struct Match: Equatable, Sendable {
        let snippetID: StoredSnippet.ID
        let keyword: String
        let deletionCount: Int
    }

    /// 送入缓冲区的输入事件分类。
    enum Input: Equatable, Sendable {
        case text(String)
        case deleteBackward
        case reset
        case ignored
    }

    /// 缓冲区超过该时长无输入即视为新旧输入无关，需清空。
    static let timeout: TimeInterval = 15
    /// 缓冲区最大长度，防止无限增长。
    static let maximumBufferLength = 256

    private(set) var keywords: [Keyword] = []
    private(set) var buffer = ""
    private var lastInputAt: Date?

    init(keywords: [Keyword] = []) {
        update(keywords)
    }

    /// 重建关键词表（过滤空值与过长删除数，按长度倒序、ID 升序）并清空缓冲区。
    mutating func update(_ keywords: [Keyword]) {
        self.keywords =
            keywords
            .filter { !$0.value.isEmpty && $0.deletionCount <= Self.maximumBufferLength }
            .sorted {
                if $0.value.count != $1.value.count { return $0.value.count > $1.value.count }
                return $0.snippetID < $1.snippetID
            }
        reset()
    }

    /// 处理一次输入：维护缓冲区，并以最长后缀匹配返回命中的关键词。
    mutating func process(_ input: Input, at now: Date) -> Match? {
        if case .ignored = input { return nil }
        if let lastInputAt, now.timeIntervalSince(lastInputAt) > Self.timeout {
            reset()
        }

        switch input {
        case .ignored:
            return nil
        case .reset:
            reset()
            return nil
        case .deleteBackward:
            lastInputAt = now
            if !buffer.isEmpty { buffer.removeLast() }
            return nil
        case .text(let text):
            lastInputAt = now
            buffer.append(text)
            if buffer.count > Self.maximumBufferLength {
                buffer.removeFirst(buffer.count - Self.maximumBufferLength)
            }
        }

        let normalizedBuffer = buffer.lowercased()
        guard let keyword = keywords.first(where: { normalizedBuffer.hasSuffix($0.value) }) else {
            return nil
        }
        reset()
        return Match(
            snippetID: keyword.snippetID,
            keyword: keyword.value,
            deletionCount: keyword.deletionCount)
    }

    /// 清空缓冲区与计时。
    mutating func reset() {
        buffer.removeAll(keepingCapacity: true)
        lastInputAt = nil
    }

    /// 把原始按键事件分类为缓冲区输入；合成事件被忽略，安全输入或光标类按键触发重置。
    static func classifyInput(
        text: String?,
        isSynthetic: Bool,
        secureEventInputEnabled: Bool,
        isFlagsChanged: Bool,
        isKeyDown: Bool,
        hasCommandOrControl: Bool,
        isResetKey: Bool,
        isDeleteBackward: Bool
    ) -> Input {
        if isSynthetic { return .ignored }
        if secureEventInputEnabled || hasCommandOrControl || isResetKey { return .reset }
        if isFlagsChanged { return .ignored }
        guard isKeyDown else { return .ignored }
        if isDeleteBackward { return .deleteBackward }
        guard let text else { return .reset }
        return .text(text)
    }
}
