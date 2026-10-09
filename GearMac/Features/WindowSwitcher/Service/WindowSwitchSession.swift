// 文件职责：窗口切换会话状态，持有扫描得到的条目与实时 AX 句柄，并按查询排序过滤出列表行。
// 分层：Service（@MainActor @Observable）；句柄不参与观察，避免超出本次展示的生命周期。
import Foundation

/// 窗口切换的一次会话状态：快照、过滤后的行与句柄映射。
@MainActor
@Observable
final class WindowSwitchSession {
    private(set) var snapshot: [WindowSwitchEntry] = []
    /// 列表读取的行：每次查询变化只排序一次，因此一次按键只排序一次。
    private(set) var filtered: [WindowSwitchEntry] = []

    private var query = ""
    /// 实时的 AX 句柄：不参与观察，也不会在这次展示之后继续存活。
    @ObservationIgnored private var elements: [Int: WindowSwitchSweep.Element] = [:]

    /// 载入一次扫描结果并按当前查询排序。
    func present(_ snapshot: WindowSwitchSweep.Snapshot) {
        self.snapshot = WindowSwitchOrder.sorted(snapshot.entries)
        elements = snapshot.elements
        applyQuery()
    }

    /// 取指定句柄对应的实时 AX 元素。
    func element(for handle: Int) -> WindowSwitchSweep.Element? { elements[handle] }

    /// 清空会话状态。
    func reset() {
        snapshot = []
        filtered = []
        elements = [:]
        query = ""
    }

    /// 按新查询重新过滤行。
    func filter(_ query: String) {
        self.query = query
        applyQuery()
    }

    /// 根据去空格的当前查询重算过滤后的行。
    private func applyQuery() {
        filtered = WindowSwitchQuery.rank(
            snapshot, for: query.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
