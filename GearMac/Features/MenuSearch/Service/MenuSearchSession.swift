// 文件职责：维护菜单搜索的会话状态，持有目标应用、菜单快照与按查询过滤后的结果行。
// 分层：Service；`@MainActor` + `@Observable`，遍历实际在后台任务中执行，此处只保存结果。
import Foundation

/// 菜单搜索的会话状态：持有目标应用、快照与过滤后的行，并驱动一次性的后台遍历任务。
@MainActor
@Observable
final class MenuSearchSession {
    /// 执行一次菜单栏遍历并以菜单项数组返回，供测试注入替身。
    typealias WalkOperation = @Sendable (pid_t, _ showsAppleMenu: Bool) async -> [MenuSearchItem]

    /// 遍历状态：空闲、读取中、就绪。
    enum State {
        case idle
        case reading
        case ready
    }

    private(set) var state: State = .idle
    private(set) var target: MenuSearchTarget = .noApplication
    private(set) var snapshot: [MenuSearchItem] = []
    /// 列表实际读取的行：每次查询变化只过滤一次，因此一次按键只排序一次。
    private(set) var filtered: [MenuSearchItem] = []
    /// 查询是否正在收窄行：仅浏览（无查询）时列表才按菜单分组。
    private(set) var isSearching = false

    private var query = ""
    private var revision = 0
    @ObservationIgnored private var walkTask: Task<Void, Never>?
    @ObservationIgnored private let walkOperation: WalkOperation

    /// 使用真实的 AX 菜单读取实现构造默认遍历操作。
    init() {
        walkOperation = { pid, showsAppleMenu in
            await Task.detached(priority: .userInitiated) {
                let deadline = ContinuousClock.now + AXMenuAccess.walkBudget
                let application = AXMenuAccess.application(for: pid)
                let bar = AXMenuAccess.readTopLevel(in: application, deadline: deadline)
                let roots = showsAppleMenu ? bar : MenuSnapshotPolicy.excludingAppleMenu(bar)
                return MenuSnapshotPolicy.collect(roots) { ContinuousClock.now >= deadline }
            }.value
        }
    }

    /// 用自定义遍历操作构造，便于测试注入。
    init(walkOperation: @escaping WalkOperation) {
        self.walkOperation = walkOperation
    }

    /// 当前目标的显示名；自指应用或无目标时为 nil。
    var targetName: String? {
        switch target {
        case .searchable(let name), .excluded(let name), .menuLess(let name): name
        case .selfTarget, .noApplication: nil
        }
    }

    /// 直接展示给定快照（无需遍历），并立即按当前查询过滤。
    func present(target: MenuSearchTarget, snapshot: [MenuSearchItem]) {
        revision &+= 1
        walkTask?.cancel()
        walkTask = nil
        self.target = target
        self.snapshot = snapshot
        state = .ready
        applyQuery()
    }

    /// 取消上一次遍历，记录新目标后在后台重新读取菜单并更新快照。
    func startWalk(target: MenuSearchTarget, pid: pid_t, showsAppleMenu: Bool) {
        revision &+= 1
        walkTask?.cancel()
        self.target = target
        snapshot = []
        filtered = []
        state = .reading
        let revision = self.revision
        walkTask = Task { [weak self] in
            let items = await self?.walkOperation(pid, showsAppleMenu) ?? []
            guard let self, self.revision == revision else { return }
            self.snapshot = items
            self.state = .ready
            self.applyQuery()
            self.walkTask = nil
        }
    }

    /// 取消遍历并清空目标、快照、查询与状态。
    func reset() {
        revision &+= 1
        walkTask?.cancel()
        walkTask = nil
        target = .noApplication
        snapshot = []
        filtered = []
        query = ""
        isSearching = false
        state = .idle
    }

    /// 更新查询并重新过滤行。
    func filter(_ query: String) {
        self.query = query
        applyQuery()
    }

    /// 依据当前查询计算 `isSearching` 与 `filtered`；查询为空时直接使用快照。
    private func applyQuery() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        isSearching = !trimmed.isEmpty
        guard isSearching else {
            filtered = snapshot
            return
        }
        filtered = MenuSearchQuery.rank(snapshot, for: trimmed)
    }
}
