// 文件职责：按窗口记录 GearMac 上次写入后的位置与循环状态，供重复按住循环、还原与跨显示器移动使用。
// 分层：Model；通用纯逻辑容器（以 Key 参数化），仅依赖 CoreGraphics/Foundation。
import CoreGraphics
import Foundation

/// GearMac 为每个被移动窗口记住的内容。见 docs/features/window-management.md#cycling-and-restore
struct WindowActionMemory<Key: Hashable> {
    struct Record: Equatable, Sendable {
        /// GearMac 首次触碰该窗口之前它所在的位置。
        var restoreFrame: CGRect
        /// 上次写入后我们*观测到*它所在的位置——而不是我们请求的位置。见 `decide`。
        var appliedFrame: CGRect
        /// 自定义尺寸时为 nil，它从不循环，也永远不是平铺。
        var command: WindowCommand.ID?
        var step: Int
        /// 它落到了哪里；从其他任一显示器按下都会开启新的循环链。
        var screenID: Int
        var originScreenID: Int
        var at: Date
    }

    struct Decision: Equatable, Sendable {
        /// 本次按下的循环位置，直接传给 `WindowPlacementEngine.Input.step`。
        var step: Int
        /// 循环链起始的显示器，显示器循环从这里开始计 `step`。
        var originScreenID: Int
        /// `commit` 应持久化为该窗口还原点的 frame。
        var restoreFrame: CGRect
        /// 首次见到时为 false：没有可回去的位置，因此 Restore 必须什么都不做。
        var canRestore: Bool
        /// 仅当窗口仍精确停在某平铺命令留下的位置时才设置。
        var lastTileCommand: WindowCommand.ID?
    }

    /// “仍是我们留下的 frame”的容差：亚像素漂移算命中，真正拖动则不算。
    static var tolerance: CGFloat { 2 }

    /// 有上限，使长时间会话处理许多窗口时不会无限增长。
    var capacity: Int
    /// 设置后，冷却后的循环会从半屏重新开始，而非在序列中途继续。
    var cycleTimeout: TimeInterval?

    private var records: [Key: Record] = [:]
    /// 最近最少使用在前，因此淘汰就是一次 `removeFirst`。
    private var order: [Key] = []

    init(capacity: Int = 64, cycleTimeout: TimeInterval? = nil) {
        self.capacity = capacity
        self.cycleTimeout = cycleTimeout
    }

    var count: Int { records.count }

    func record(for key: Key) -> Record? { records[key] }

    /// 解算循环步进与还原点；移动器知道最终落点后由 `commit` 写入。
    func decide(
        key: Key, command: WindowCommand.ID?, currentFrame: CGRect, currentScreenID: Int,
        cycleLength: Int, now: Date
    ) -> Decision {
        // 首次见到：记录它原来的位置，使从未移动过的窗口也能 Restore。
        guard let record = records[key] else {
            return Decision(
                step: 0, originScreenID: currentScreenID, restoreFrame: currentFrame,
                canRestore: false, lastTileCommand: nil)
        }

        // 对照观测到的 frame，而非请求的 frame。见 docs/features/window-management.md
        guard approximatelyEqual(currentFrame, record.appliedFrame) else {
            return Decision(
                step: 0, originScreenID: currentScreenID, restoreFrame: currentFrame,
                canRestore: true, lastTileCommand: nil)
        }

        let lastTileCommand = record.command.flatMap {
            WindowPlacementEngine.isTileCommand($0) ? $0 : nil
        }
        let expired = cycleTimeout.map { now.timeIntervalSince(record.at) > $0 } ?? false
        // 长度为 1 同时覆盖不循环的命令与完全关闭循环的情况。
        let continues =
            cycleLength > 1 && command == record.command
            && currentScreenID == record.screenID && !expired
        return Decision(
            step: continues ? (record.step + 1) % cycleLength : 0,
            originScreenID: continues ? record.originScreenID : currentScreenID,
            restoreFrame: record.restoreFrame, canRestore: true, lastTileCommand: lastTileCommand)
    }

    /// 记录实际落点。`appliedFrame` 必须从窗口读回，不能假定。
    mutating func commit(
        key: Key, command: WindowCommand.ID?, decision: Decision, appliedFrame: CGRect,
        screenID: Int, now: Date
    ) {
        records[key] = Record(
            restoreFrame: decision.restoreFrame, appliedFrame: appliedFrame, command: command,
            step: decision.step, screenID: screenID, originScreenID: decision.originScreenID,
            at: now)
        touch(key)
    }

    /// 断开循环链但保留还原点，这正是全屏所需。
    mutating func forgetCycle(key: Key) {
        guard var record = records[key] else { return }
        record.step = 0
        record.originScreenID = record.screenID
        records[key] = record
    }

    mutating func forget(where predicate: (Key) -> Bool) {
        let doomed = records.keys.filter(predicate)
        guard !doomed.isEmpty else { return }
        for key in doomed { records.removeValue(forKey: key) }
        order.removeAll { doomed.contains($0) }
    }

    mutating func forget(key: Key) {
        guard records.removeValue(forKey: key) != nil else { return }
        order.removeAll { $0 == key }
    }

    private mutating func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > capacity, let oldest = order.first {
            order.removeFirst()
            records.removeValue(forKey: oldest)
        }
    }

    private func approximatelyEqual(_ a: CGRect, _ b: CGRect) -> Bool {
        let tolerance = Self.tolerance
        return abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }
}
