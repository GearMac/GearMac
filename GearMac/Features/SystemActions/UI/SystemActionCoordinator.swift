// 文件职责：系统动作的统一调度入口，负责确认闸门、执行、音量 HUD 与失败提示。
// 分层：Coordinator；持有 PaletteCoordinator 与 VolumeHUD，UI 展示委托给 AppCore。
import AppKit

/// 系统动作及其闸门与反馈的唯一调度入口。
@MainActor
final class SystemActionCoordinator {
    private let paletteCoordinator: PaletteCoordinator
    private var isTogglingMicrophone = false
    @ObservationIgnored private lazy var volumeHUD = VolumeHUDController(settings: core.settings)
    /// 仅用于对话框与消息 HUD 展示——绝不用于本类型自己持有的状态。
    private unowned let core: AppCore

    init(paletteCoordinator: PaletteCoordinator, core: AppCore) {
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    /// 所有触发路径的唯一入口，任何闸门都无法绕过。
    func runSystemAction(id: SystemAction.ID) {
        let target = paletteCoordinator.targetApp
        if paletteCoordinator.isVisible { paletteCoordinator.hidePalette(restoreFocus: false) }
        Task { await perform(SystemActionCatalog.action(id: id), previousApp: target) }
    }

    /// 执行单个动作：先过确认闸门，再分派到执行器或专用流程。
    private func perform(_ action: SystemAction, previousApp: NSRunningApplication?) async {
        if action.id == .toggleMicrophoneMute {
            guard !isTogglingMicrophone else { return }
            isTogglingMicrophone = true
        }
        defer {
            if action.id == .toggleMicrophoneMute { isTogglingMicrophone = false }
        }
        let language = core.settings.language
        switch action.confirmation {
        case .computed:
            await quitAllApps()
            return
        case .followsFinder where !SystemActionRunner.finderWarnsBeforeEmptyingTrash:
            break
        case .required(let title, let message), .followsFinder(let title, let message):
            guard
                await core.confirm(
                    title: L10n.string(title, language: language),
                    message: L10n.string(message, language: language), symbol: action.sfSymbol,
                    confirmTitle: action.localizedTitle(language))
            else { return }
        case .none:
            break
        }
        do {
            var feedback: SystemActionFeedback?
            if action.id == .setVolume {
                let current = try SystemActionRunner.currentVolume()
                guard let selected = await core.pickVolume(current: current) else { return }
                try SystemActionRunner.setVolume(selected)
            } else {
                feedback = try await SystemActionRunner.run(action.id, previousApp: previousApp)
            }
            if Self.showsVolumeFeedback.contains(action.id) {
                let state = try SystemActionRunner.outputState()
                volumeHUD.show(level: state.level, muted: state.muted)
            } else if let feedback {
                core.showMessage(
                    feedback.localizedTitle(core.settings.language),
                    tone: feedback.isNoOp ? .neutral : .success)
            }
        } catch let failure as SystemActionFailure {
            await presentFailure(action: action, failure: failure)
        } catch {
            await presentFailure(
                action: action, failure: SystemActionFailure(text: error.localizedDescription))
        }
    }

    /// 音量与静音相关动作；macOS 只会在真实媒体键按下时绘制 HUD。
    private static let showsVolumeFeedback: Set<SystemAction.ID> = [
        .setVolume, .volumeUp, .volumeDown, .toggleMute,
        .volume0, .volume25, .volume50, .volume75, .volume100
    ]

    /// 供执行器内部的异步完成回调调用的同步入口，那些回调无法 await。
    func presentSystemActionFailure(id: SystemAction.ID, failure: SystemActionFailure) {
        Task { await presentFailure(action: SystemActionCatalog.action(id: id), failure: failure) }
    }

    /// 展示失败提示，并在需要时跳转到对应的系统设置面板。
    private func presentFailure(action: SystemAction, failure: SystemActionFailure) async {
        let language = core.settings.language
        guard
            await core.reportFailure(
                title: String(
                    format: L10n.string(SystemActionsKey.failureTitle, language: language),
                    action.localizedTitle(language)),
                message: failure.localizedMessage(language),
                symbol: action.sfSymbol,
                recovery: failure.settings == nil
                    ? nil : L10n.string(SystemActionsKey.openSystemSettings, language: language)),
            let settings = failure.settings
        else { return }
        let pane: String
        switch settings {
        case .accessibility: pane = "Privacy_Accessibility"
        case .automation: pane = "Privacy_Automation"
        case .bluetooth: pane = "Privacy_Bluetooth"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Quit All 先弹确认，解析出的列表同时用于计数与终止。
    private func quitAllApps() async {
        let targets = AppLauncher.quitAllTargets()
        let language = core.settings.language
        let title =
            targets.count == 1
            ? L10n.string(SystemActionsKey.confirmQuitAllOne, language: language)
            : String(
                format: L10n.string(SystemActionsKey.confirmQuitAllMany, language: language), targets.count)
        guard !targets.isEmpty,
            await core.confirm(
                title: title,
                message: L10n.string(SystemActionsKey.confirmQuitAllMessage, language: language),
                symbol: SystemActionCatalog.action(id: .quitAllApps).sfSymbol,
                confirmTitle: L10n.string(SystemActionsKey.confirmQuitAll, language: language))
        else { return }
        for app in targets { app.terminate() }
    }
}
