// 文件职责：卸载面板的会话状态机——承载一次扫描的计划、勾选集合与执行状态。
// 分层：Service（Uninstall）；`@MainActor` 状态持有者，扫描与体积测量通过子任务异步执行。
import Foundation

/// 一次扫描及其计划与勾选集合；勾选集合的不变量由别处维护。
@MainActor
@Observable
final class UninstallSession {
    /// 卸载会话的状态。
    enum State: Equatable {
        case idle
        case scanning
        case ready(UninstallPlan)
        case failed(ScanFailure)
    }

    /// 扫描失败的可本地化原因；由界面按当前语言渲染。
    enum ScanFailure: Equatable, Sendable {
        case refused
        /// 未能归类的原因，附系统给出的描述。
        case other(String)

        /// 把扫描抛出的错误归类为可本地化的失败原因。
        init(_ error: Error) {
            if let failure = error as? UninstallScanner.Failure {
                switch failure {
                case .refused: self = .refused
                }
            } else {
                self = .other(error.localizedDescription)
            }
        }

        /// 按语言渲染失败说明。
        func message(_ language: AppLanguage) -> String {
            switch self {
            case .refused:
                return L10n.string(UninstallKey.scanRefused, language: language)
            case .other(let detail):
                return String(
                    format: L10n.string(UninstallKey.scanFailed, language: language), detail)
            }
        }
    }

    private(set) var state: State = .idle
    private(set) var selection: UninstallSelection?
    private(set) var isTrashing = false
    /// 保留用于确认文案与卸载后的引用清理。
    private(set) var app: AppEntry?

    @ObservationIgnored private var scanTask: Task<Void, Never>?

    var plan: UninstallPlan? {
        if case .ready(let plan) = state { return plan }
        return nil
    }

    var candidates: [UninstallCandidate] { plan?.candidates ?? [] }
    var selectedCount: Int { selection?.count ?? 0 }
    var selectedBytes: Int64 {
        guard let plan, let selection else { return 0 }
        return selection.bytes(in: plan)
    }
    var selectedCandidates: [UninstallCandidate] {
        guard let plan, let selection else { return [] }
        return selection.candidates(in: plan)
    }
    var canConfirm: Bool { selectedCount > 0 && !isTrashing }

    /// 开始一次扫描：重置状态并在后台发现候选，随后流式测量目录体积。
    func begin(app: AppEntry, otherAppNames: [String], otherBundleIDs: [String], isRunning: Bool) {
        cancel()
        self.app = app
        state = .scanning
        selection = nil
        let url = app.url
        let name = app.name
        let bundleID = app.bundleID
        scanTask = Task(priority: .userInitiated) { [weak self] in
            let result = await Self.runDiscovery(
                url: url, name: name, bundleID: bundleID, otherAppNames: otherAppNames,
                otherBundleIDs: otherBundleIDs, isRunning: isRunning)
            guard let self, !Task.isCancelled else { return }
            switch result {
            case .success(let plan):
                state = .ready(plan)
                selection = plan.defaultSelection
                await measurePending(in: plan)
            case .failure(let error):
                state = .failed(ScanFailure(error))
            }
        }
    }

    /// 释放进行中的扫描；面板离开屏幕时调用。
    func cancel() {
        scanTask?.cancel()
        scanTask = nil
        state = .idle
        selection = nil
        app = nil
    }

    /// 切换某个候选的勾选状态。
    func toggle(_ id: UninstallCandidate.ID) {
        guard let plan else { return }
        selection?.toggle(id, in: plan)
    }

    /// 更新是否正在执行移入废纸篓。
    func setTrashing(_ trashing: Bool) {
        isTrashing = trashing
    }

    /// 列表行已在屏幕上，因此每次遍历只写回自己那一行，而不阻塞整个列表。
    private func measurePending(in plan: UninstallPlan) async {
        let paths = plan.candidates.filter { $0.size == nil }.map(\.path)
        guard !paths.isEmpty else { return }
        await UninstallScanner.measure(paths: paths) { [weak self] path, size in
            guard let self, case .ready(var plan) = state else { return }
            plan.setSize(size, forPath: path)
            state = .ready(plan)
        }
    }

    /// 在非主线程执行，且是 `scanTask` 的子任务：这正是 `cancel()` 能真正终止扫描的原因。
    private nonisolated static func runDiscovery(
        url: URL, name: String, bundleID: String?, otherAppNames: [String],
        otherBundleIDs: [String], isRunning: Bool
    ) async -> Result<UninstallPlan, Error> {
        do {
            return .success(
                try await UninstallScanner.discover(
                    target: makeTarget(url: url, name: name, bundleID: bundleID),
                    otherAppNames: otherAppNames, otherBundleIDs: otherBundleIDs,
                    isTargetRunning: isRunning))
        } catch {
            return .failure(error)
        }
    }

    /// 在非主线程执行：它会打开应用包文件。
    private nonisolated static func makeTarget(
        url: URL, name: String, bundleID: String?
    )
        -> UninstallTarget
    {
        let info = Bundle(url: url)?.infoDictionary
        return UninstallTarget(
            bundleURL: url, bundleID: bundleID,
            displayName: AppDisplayName.named(info?["CFBundleDisplayName"]) ?? name,
            bundleName: info?["CFBundleName"] as? String)
    }
}
