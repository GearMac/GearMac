// 文件职责：维护「顺序粘贴」遍历剪贴板历史的游标、剪贴板变更基准与粘贴节流时间。
// 分层：Model；保持纯净，不得 import AppKit/SwiftUI，自身不访问剪贴板。
import Foundation

/// 「顺序粘贴」沿历史自新到旧的遍历；遍历开始时快照即冻结。
struct PasteSequence: Sendable {
    /// 两次粘贴间隔超过该时长即视为新的一次遍历。
    static let idleTimeout: TimeInterval = 60
    /// 长于 ⌘V 的投递延迟与目标读取时间，使下一次写入不会抢在该读取之前。
    static let settleInterval: TimeInterval = 0.25

    /// 保存 id 而非条目本身，使遍历途中被删除的条目会被跳过，而不是照旧粘贴。
    private let entryIDs: [ClipboardItem.ID]
    private var nextIndex = 0
    /// 我们上次写入后剪贴板的变更计数；计数不同说明其间发生了新的复制。
    private var changeCount: Int
    /// 上一次记录粘贴的时间，用于空闲超时与 settle 节流判断。
    private var lastPaste: Date

    /// 以当前历史快照、剪贴板变更计数与起始时间创建一次遍历。
    init(history: [ClipboardItem], changeCount: Int, now: Date) {
        entryIDs = history.map(\.id)
        self.changeCount = changeCount
        lastPaste = now
    }

    /// 剪贴板未被别人改动且未超时，则视为同一次遍历的延续。
    func continues(changeCount: Int, at now: Date) -> Bool {
        changeCount == self.changeCount && now.timeIntervalSince(lastPaste) < Self.idleTimeout
    }

    /// 距上次粘贴是否仍在 settle 间隔内（此时不应开始下一次写入）。
    func isSettling(at now: Date) -> Bool {
        now.timeIntervalSince(lastPaste) < Self.settleInterval
    }

    /// 走到末尾返回 nil，此时停止而不会绕回最新条目。
    mutating func next(in history: [ClipboardItem]) -> ClipboardItem? {
        while nextIndex < entryIDs.endIndex {
            let id = entryIDs[nextIndex]
            nextIndex += 1
            // 两侧都是最新在前，因此扫描深度与已遍历的深度大致相当。
            if let item = history.first(where: { $0.id == id }) { return item }
        }
        return nil
    }

    /// 我们自己的写入也会改变计数，因此遍历将其采纳为新基准，而不视作新的复制。
    mutating func recordPaste(changeCount: Int, at now: Date) {
        self.changeCount = changeCount
        lastPaste = now
    }
}
