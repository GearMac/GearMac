// 文件职责：执行卸载——把选中的候选逐个移入废纸篓并汇总结果。
// 分层：Service（Uninstall）；唯一删除入口是 `trashItem`，保证卸载始终可撤销。
import Foundation

/// 一个未能移入废纸篓的条目及其原因。
struct UninstallFailedItem: Hashable, Sendable {
    let name: String
    let reason: String
}

/// 一次卸载的结果汇总。
struct UninstallReport: Sendable {
    let trashed: [UninstallCandidate]
    let failed: [UninstallFailedItem]

    var trashedCount: Int { trashed.count }
    var freedBytes: Int64 { trashed.reduce(0) { $0 + ($1.size?.bytes ?? 0) } }
    var hasFailures: Bool { !failed.isEmpty }
    /// 用于决定是否做引用清理：只删残留而没删应用包时，App 仍处于已安装状态。
    var removedBundle: Bool { trashed.contains { $0.evidence == .bundle } }
}

/// 这里唯一的删除调用是 `trashItem`，因此卸载始终可撤销。
enum UninstallRunner {
    /// 在后台线程把候选逐个移入废纸篓，返回成功与失败明细。
    static func moveToTrash(_ candidates: [UninstallCandidate]) async -> UninstallReport {
        // 被锁定的候选本不该被勾选；直接跳过而不尝试删除。
        let removable = candidates.filter { !$0.isLocked }
        // 应用包放在最后删除，部分失败时它仍在，便于重跑。
        let ordered =
            removable.filter { $0.evidence != .bundle } + removable.filter { $0.evidence == .bundle }

        return await Task.detached(priority: .userInitiated) {
            var trashed: [UninstallCandidate] = []
            var failed: [UninstallFailedItem] = []
            for candidate in ordered {
                do {
                    try FileManager.default.trashItem(at: candidate.url, resultingItemURL: nil)
                    trashed.append(candidate)
                } catch {
                    failed.append(
                        UninstallFailedItem(
                            name: candidate.name, reason: error.localizedDescription))
                }
            }
            return UninstallReport(trashed: trashed, failed: failed)
        }.value
    }
}
