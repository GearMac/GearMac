// 文件职责：命令输出窗口的状态模型与窗口控制：维护当前运行的日志、增量与结果，并驱动输出视图。
// 分层：UI（Presenter）；@MainActor，复用同一个窗口，新一次运行只替换展示内容而不会取消上一次。
import Foundation

/// 运行结束后的结果。
struct CommandOutcome: Sendable {
    let summary: String
    /// 当退出状态能指明原因时，给出针对可修复失败的提示。
    let hint: String?
    let succeeded: Bool
    let finishedAt: Date
}

/// 某条命令的一次运行，从它启动那一刻开始记录。
struct CommandRun: Identifiable, Sendable {
    let id = UUID()
    /// 对应哪条自定义命令，供窗口再次运行。
    let commandID: UUID
    let name: String
    /// 展示在名称下方的 shell 文本——只写 "brew" 说明不了实际执行了什么。
    let commandText: String
    let symbol: String
    let startedAt: Date
    /// 到目前为止打印的全部内容，用于复制以及整体重绘。
    var log = ""
    /// 相对上一版只前进一步时，视图直接追加它而不遍历整个日志。
    var delta = ""
    var revision = 0
    /// `log` 头部被丢弃时自增，作为文本视图整体重绘的信号。
    var generation = 0
    /// 命令仍在运行时为 nil。
    var outcome: CommandOutcome?

    var isRunning: Bool { outcome == nil }
}

/// 复用同一个窗口：第二次运行只替换所展示的内容，绝不取消第一次。
@MainActor
@Observable
final class CommandOutputPresenter {
    /// 超过此长度就丢弃头部：命令的结局写在尾部。
    private static let logLimit = 256 * 1024

    private(set) var run: CommandRun?

    @ObservationIgnored private let activation: ActivationPolicy
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let rerun: (UUID) -> Void
    @ObservationIgnored private let stop: (UUID) -> Void
    @ObservationIgnored private let openSettings: () -> Void
    @ObservationIgnored private lazy var window = AppWindowController(
        title: settings.text(CustomCommandsKey.outputTitle), contentSize: CommandOutputView.initialSize,
        resizable: true,
        autosaveName: "CommandOutputWindow", activation: activation, closesOnEscape: true)

    /// 注入激活策略与窗口按钮所需的重跑、停止、打开设置回调。
    init(
        settings: AppSettings, activation: ActivationPolicy, rerun: @escaping (UUID) -> Void,
        stop: @escaping (UUID) -> Void, openSettings: @escaping () -> Void
    ) {
        self.settings = settings
        self.activation = activation
        self.rerun = rerun
        self.stop = stop
        self.openSettings = openSettings
    }

    /// 以一条空白的运行中命令打开窗口，返回本次运行的 id（后续上报都以它为准）。
    @discardableResult
    func begin(commandID: UUID, name: String, commandText: String, symbol: String) -> UUID {
        let run = CommandRun(
            commandID: commandID, name: name, commandText: commandText, symbol: symbol,
            startedAt: Date())
        self.run = run
        window.show { CommandOutputView(presenter: self, settings: settings) }
        return run.id
    }

    /// 追加一段输出；超出长度上限时丢弃日志头部并提升 generation。
    func append(_ text: String, to id: UUID) {
        guard var run, run.id == id else { return }
        run.log += text
        run.delta = text
        run.revision += 1
        if run.log.utf8.count > Self.logLimit {
            run.log = String(run.log.suffix(Self.logLimit / 2))
            // 此时 delta 已无法描述这次变化，于是改让视图整体重绘。
            run.generation += 1
        }
        self.run = run
    }

    /// 记录本次运行的结果。
    func finish(_ outcome: CommandOutcome, for id: UUID) {
        guard var run, run.id == id else { return }
        run.outcome = outcome
        self.run = run
    }

    // MARK: - Actions the window offers

    /// 再次运行当前命令。
    func runAgain() {
        guard let run else { return }
        rerun(run.commandID)
    }

    /// 停止仍在运行的命令。
    func stopRunning() {
        guard let run, run.isRunning else { return }
        stop(run.id)
    }

    /// 打开命令设置面板。
    func showCommandSettings() {
        openSettings()
    }

    /// 若输出窗口已存在则将其前置；不存在时返回 false，以便调用方另行打开。
    func focusExisting() -> Bool {
        window.focus()
    }
}
