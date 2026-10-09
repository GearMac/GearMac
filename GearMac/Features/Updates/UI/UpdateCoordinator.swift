// 文件职责：编排更新窗口的完整流程，维护检查、提示、安装与重启各阶段的状态机。
// 分层：Coordinator（@MainActor @Observable）；安装动作交给 UpdateInstaller，窗口由 AppWindowController 承载。
import AppKit
import SwiftUI

/// 安装器只在本协调器判定安全之后才会执行更新。
@MainActor
@Observable
final class UpdateCoordinator {
    /// 提示、进度与结果共用同一个界面：下载过程无法迁移到对话框中进行。
    enum Stage: Equatable {
        case checking
        case upToDate
        /// 本地构建没有可比对的发布流，因此如实说明而不是假装有更新。
        case localBuild
        case available(AvailableRelease)
        case blocked(UpdateReadiness.Blocker, AvailableRelease)
        case installing(AvailableRelease, UpdateInstaller.Phase)
        case readyToRelaunch
        case failed(UpdateFailure)
    }

    private(set) var stage: Stage = .checking

    private let store: UpdateCheckStore
    /// 仅用于注入环境与读取活动状态；绝不用于本类型自己拥有的状态。
    private unowned let core: AppCore
    @ObservationIgnored private lazy var window = AppWindowController(
        title: core.settings.text(UpdatesKey.windowTitle),
        contentSize: UpdateWindowView.initialSize,
        activation: core.activationPolicy)
    @ObservationIgnored private var installTask: Task<Void, Never>?

    init(store: UpdateCheckStore, core: AppCore) {
        self.store = store
        self.core = core
    }

    var channel: ReleaseChannel { store.channel }
    var runningVersion: String {
        store.runningVersion?.description ?? core.settings.text(UpdatesKey.versionUnknown)
    }

    /// 本地构建没有发布流，因此也不对外暴露该命令。
    func applyEnabled() {
        core.appIndex.setCommandsVisible([.checkForUpdates], store.channel.updatesItself)
    }

    /// 依据设置启动或停止自动检查。
    func applyAutomaticChecking() {
        if core.settings.automaticallyCheckForUpdates {
            store.start()
        } else {
            store.stop()
        }
    }

    /// 若窗口已存在则将其置前。
    func focusExisting() -> Bool {
        window.focus()
    }

    /// 窗口采用内容实测高度，因此各阶段都不需要用空白凑高度。
    func fit(height: CGFloat) {
        window.fitContent(width: UpdateWindowView.width, height: height)
    }

    // MARK: - Entry points

    /// 手动操作：始终打开窗口，并始终向 GitHub 发起请求。
    func checkForUpdates() {
        guard store.channel.updatesItself else {
            stage = .localBuild
            present()
            return
        }
        if case .installing = stage {
            present()
            return
        }
        stage = .checking
        present()
        Task { [weak self] in
            guard let self else { return }
            let answered = await store.check()
            guard case .checking = stage else { return }
            if let release = store.update {
                stage = .available(release)
            } else if answered {
                stage = .upToDate
            } else {
                stage = .failed(.downloadFailed(core.settings.text(UpdatesKey.failReachGitHub)))
            }
        }
    }

    /// 自动路径：返回 `false` 表示本次暂缓了提示，store 会稍后重新提供。
    func presentIfAvailable(_ release: AvailableRelease) -> Bool {
        guard core.settings.automaticallyCheckForUpdates else { return false }
        switch stage {
        // 已在处理中：重新提供会丢掉已完成的下载或它应得的那次重启。
        case .installing, .readyToRelaunch:
            return true
        case .checking, .upToDate, .localBuild, .available, .blocked, .failed:
            guard UpdateReadiness.evaluate(core.currentActivity) == nil else { return false }
            stage = .available(release)
            present()
            return true
        }
    }

    // MARK: - Actions

    /// 开始安装：点击瞬间再次校验活动状态，随后进入安装阶段。
    func install() {
        guard let release = pendingRelease else { return }
        // 在点击瞬间重新询问，而不是读取可能已失效的标志位。
        if let blocker = UpdateReadiness.evaluate(core.currentActivity) {
            stage = .blocked(blocker, release)
            return
        }
        stage = .installing(release, .downloading(received: 0, expected: release.assetSize))
        let installer = self.installer
        // 提到外层：把主线程切换嵌到任务体会重新捕获其弱引用的 `self`。
        let onProgress: @Sendable (UpdateInstaller.Phase) -> Void = { [weak self] phase in
            Task { @MainActor in self?.report(phase, for: release) }
        }
        installTask = Task { [weak self] in
            do {
                try await installer.install(release, onProgress: onProgress)
                self?.stage = .readyToRelaunch
            } catch is CancellationError {
                self?.stage = .available(release)
            } catch let failure as UpdateFailure {
                self?.stage = .failed(failure)
            } catch {
                self?.stage = .failed(.downloadFailed(error.localizedDescription))
            }
        }
    }

    /// 跳过一个版本即可让它不再询问；更高的版本仍会再次提示。
    func skip() {
        if let release = pendingRelease { store.skip(release) }
        window.close()
    }

    /// 取消进行中的安装任务。
    func cancelInstall() {
        installTask?.cancel()
        installTask = nil
    }

    /// 回到可安装状态以便用户重试。
    func retry() {
        guard let release = pendingRelease else { return }
        stage = .available(release)
    }

    /// 关闭更新窗口。
    func dismiss() {
        window.close()
    }

    /// 使用 `NSApp.terminate` 而非 `exit`：它会落盘便签草稿并归还 HID 重映射。
    func relaunch() {
        RelaunchRunner.relaunchAfterExit(Bundle.main.bundleURL)
        NSApp.terminate(nil)
    }

    // MARK: - Private

    /// 仅在仍处于安装阶段时更新进度。
    private func report(_ phase: UpdateInstaller.Phase, for release: AvailableRelease) {
        guard case .installing = stage else { return }
        stage = .installing(release, phase)
    }

    /// 当前阶段关联的、或已就绪待处理的发布版本。
    private var pendingRelease: AvailableRelease? {
        switch stage {
        case .available(let release), .blocked(_, let release), .installing(let release, _):
            return release
        case .checking, .upToDate, .localBuild, .readyToRelaunch, .failed:
            return store.update
        }
    }

    /// 针对当前应用包与缓存目录构造的安装器。
    private var installer: UpdateInstaller {
        UpdateInstaller(
            bundleURL: Bundle.main.bundleURL,
            stagingDirectory: AppPaths.caches().appendingPathComponent("Updates", isDirectory: true))
    }

    /// 显示（或复用）承载更新界面的窗口。
    private func present() {
        window.show {
            UpdateWindowView()
                .environment(self)
                .environment(self.core.settings)
        }
    }
}
