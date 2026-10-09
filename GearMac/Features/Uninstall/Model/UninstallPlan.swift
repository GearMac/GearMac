// 文件职责：卸载计划的数据模型——候选条目、测量体积、计划与勾选集合。
// 分层：Model（Uninstall）；保持纯净，不做任何文件系统访问。
import Foundation

/// 字节数，并记录遍历是否触及预算，使超大目录能如实显示为「至少」。
struct MeasuredSize: Hashable, Sendable {
    var bytes: Int64 = 0
    var isLowerBound = false

    static let zero = MeasuredSize()

    /// 人类可读的体积文本；结果为下界时加前缀 “≥”。
    var formatted: String {
        // 否则空文件夹会显示成 “Zero kB”，看起来像缺陷。
        let size = bytes.formatted(.byteCount(style: .file, spellsOutZero: false))
        return isLowerBound ? "≥ " + size : size
    }
}

/// 卸载会移入废纸篓的一个条目：应用包本身，或归属它的残留文件。
struct UninstallCandidate: Identifiable, Hashable, Sendable {
    /// 已标准化处理的路径，也是 `UninstallSelection` 存储的标识。
    let path: String
    /// 列表行标题；应用包会去掉 `.app` 后缀。
    let name: String
    /// 列表行副标题：所在目录，用 `~` 缩写。
    let locationLabel: String
    let evidence: UninstallEvidence
    let isDirectory: Bool
    /// 目录遍历完成前为 nil；文件的体积直接来自 `lstat`。
    var size: MeasuredSize?
    let protection: UninstallProtection

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }
    var isLocked: Bool { !protection.isRemovable }
    /// 该条目不能移除的原因；可移除时为 nil。
    func localizedLockReason(_ language: AppLanguage) -> String? {
        protection.localizedLockReason(language)
    }
}

/// 归属于单个 App 的全部条目，应用包固定在首位。
struct UninstallPlan: Equatable, Sendable {
    let target: UninstallTarget
    var candidates: [UninstallCandidate]
    let isTargetRunning: Bool

    /// 所有可移除候选的 ID 集合。
    var removableIDs: Set<UninstallCandidate.ID> {
        Set(candidates.lazy.filter { !$0.isLocked }.map(\.id))
    }

    var lockedCount: Int { candidates.count { $0.isLocked } }

    var totalBytes: Int64 { candidates.reduce(0) { $0 + ($1.size?.bytes ?? 0) } }

    /// 所有可移除项（含按名称匹配的）：精确、受限且可撤销。
    var defaultSelection: UninstallSelection {
        UninstallSelection(plan: self, checked: removableIDs)
    }

    /// 让一次体积遍历写回它所测量的行，且不扰动顺序与勾选集合。
    mutating func setSize(_ size: MeasuredSize, forPath path: String) {
        guard let index = candidates.firstIndex(where: { $0.path == path }) else { return }
        candidates[index].size = size
    }
}

/// 勾选集合的唯一持有者；构造时取一次交集即可把被锁定的候选排除在外。
struct UninstallSelection: Equatable, Sendable {
    private(set) var checked: Set<UninstallCandidate.ID>

    init(plan: UninstallPlan, checked: Set<UninstallCandidate.ID> = []) {
        self.checked = checked.intersection(plan.removableIDs)
    }

    /// 切换某个候选的勾选状态；被锁定的候选无法被勾选。
    mutating func toggle(_ id: UninstallCandidate.ID, in plan: UninstallPlan) {
        if checked.contains(id) {
            checked.remove(id)
        } else if plan.removableIDs.contains(id) {
            checked.insert(id)
        }
    }

    func isChecked(_ id: UninstallCandidate.ID) -> Bool { checked.contains(id) }

    var count: Int { checked.count }

    /// 已勾选候选的字节总和。
    func bytes(in plan: UninstallPlan) -> Int64 {
        plan.candidates.reduce(0) { $0 + (checked.contains($1.id) ? ($1.size?.bytes ?? 0) : 0) }
    }

    /// 按计划中的原始顺序列出已勾选的候选。
    func candidates(in plan: UninstallPlan) -> [UninstallCandidate] {
        plan.candidates.filter { checked.contains($0.id) }
    }
}
