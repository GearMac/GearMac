// 文件职责：编排听写全流程（快捷键/按钮触发、采集、推理、插入与状态展示）。
// 分层：Coordinator/@MainActor；唯一持有阶段状态，通过 token 丢弃过期会话。
import AppKit
import AVFoundation

/// 听写协调器：管理从按键到文本插入的完整状态机。
@MainActor
@Observable
final class DictationCoordinator {
    /// 听写会话的阶段。
    private enum Phase { case idle, starting, listening, transcribing, stopping }

    private let settings: AppSettings
    private let hotKeys: HotKeyManager
    let models: DictationModelStore
    private let capture = DictationCapture()
    private let audioDucker: DictationAudioDucker
    private let panel = DictationPanelController()
    private let injector: TextInjector
    private let showMessage: (String, DialogTone) -> Void
    private let confirmEnable: () async -> Bool
    @ObservationIgnored private var phase: Phase = .idle
    @ObservationIgnored private var token = UUID()
    @ObservationIgnored private var enableTask: Task<Void, Never>?
    @ObservationIgnored private var startTask: Task<Void, Never>?
    @ObservationIgnored private var transcriptionTask: Task<Void, Never>?
    @ObservationIgnored private var stopTask: Task<Void, Never>?
    @ObservationIgnored private var finishWhenStarted = false
    @ObservationIgnored private var target: InjectionTarget?
    /// 当前麦克风按钮所属的输入框；通过快捷键发起的会话为 nil。
    private(set) var field: DictationField?

    /// 注入设置、快捷键、模型存储与插入器，并接线面板与采集回调。
    init(
        settings: AppSettings, hotKeys: HotKeyManager, models: DictationModelStore,
        injector: TextInjector, audioDucker: DictationAudioDucker,
        confirmEnable: @escaping () async -> Bool,
        showMessage: @escaping (String, DialogTone) -> Void
    ) {
        self.settings = settings
        self.hotKeys = hotKeys
        self.models = models
        self.injector = injector
        self.audioDucker = audioDucker
        self.confirmEnable = confirmEnable
        self.showMessage = showMessage
        panel.onAccept = { [weak self] in self?.accept() }
        panel.onCancel = { [weak self] in self?.cancel() }
        capture.onLevels = { [weak self] in self?.panel.state.levels = $0 }
        capture.onLimit = { [weak self] in self?.accept() }
    }

    /// 启用/停用听写，启用时经用户确认并申请麦克风权限。
    func setEnabled(_ enabled: Bool) {
        guard enabled != settings.dictationEnabled else { return }
        guard enabled else {
            settings.dictationEnabled = false
            enableTask?.cancel()
            cancel()
            return
        }
        guard enableTask == nil else { return }
        NSApp.activate()
        enableTask = Task { [weak self] in
            guard let self else { return }
            defer { enableTask = nil }
            guard await confirmEnable(), !Task.isCancelled else { return }
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            guard !Task.isCancelled else { return }
            guard granted else {
                showMessage(settings.text(DictationKey.micPermissionMessage), .danger)
                return
            }
            settings.dictationEnabled = true
            if settings.dictationDestination.pastes { Permissions.ensureAccessibility() }
        }
    }

    /// 下载指定模型，取消类错误静默处理，其余错误弹提示。
    func downloadModel(_ model: DictationModel) async {
        do { try await models.download(model) } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch { showMessage(error.localizedDescription, .danger) }
    }

    /// 删除已安装的模型，失败时弹提示。
    func removeModel(_ model: DictationModel) async {
        do { try await models.delete(model) } catch { showMessage(error.localizedDescription, .danger) }
    }

    /// 校验按住说话所需的快捷键配置，返回错误文案或 nil。
    var holdShortcutIssue: String? {
        guard let binding = hotKeys.binding(for: .dictation) else { return nil }
        guard binding.shortcut != nil || binding.holdKey != nil else {
            return settings.text(DictationKey.holdIssueModifier)
        }
        if let owner = hotKeys.conflictOwner(of: binding, excluding: .dictation) {
            return String(
                format: settings.text(DictationKey.holdIssueConflict), owner)
        }
        return nil
    }

    /// 快捷键按下：校验前置条件后开始采集，toggle 模式下再次按下则结束。
    func pressed() {
        guard settings.dictationEnabled else { return }
        if phase == .stopping { return }
        if settings.dictationMode == .pushToTalk,
            hotKeys.binding(for: .dictation)?.shortcut == nil,
            hotKeys.binding(for: .dictation)?.holdKey == nil
        {
            showMessage(settings.text(DictationKey.holdNeedsShortcut), .danger)
            return
        }
        if phase != .idle {
            if settings.dictationMode == .toggle { finish() }
            return
        }
        begin(target: InjectionTarget.current())
    }

    /// 听写是否已在设置中启用。
    var isEnabled: Bool { settings.dictationEnabled }
    /// 当前选中的模型是否已安装。
    var hasModel: Bool { models.isInstalled(settings.dictationModel) }

    /// 输入框自带麦克风：点击开始、再次点击结束，不受快捷键模式或焦点影响。
    func toggle(into editor: any InjectableTextView) {
        guard settings.dictationEnabled, phase != .stopping else { return }
        guard phase == .idle else {
            if field?.editor == ObjectIdentifier(editor) { finish() }
            return
        }
        field = DictationField(editor: ObjectIdentifier(editor))
        begin(target: .ownEditor(editor))
    }

    /// 结束当前会话：启动中则标记为待结束，否则直接接受。
    private func finish() {
        if phase == .starting {
            finishWhenStarted = true
        } else {
            accept()
        }
    }

    /// 校验模型已安装后开始一次采集会话，并用 token 判定会话是否仍有效。
    private func begin(target: InjectionTarget?) {
        guard models.isInstalled(settings.dictationModel) else {
            field = nil
            showMessage(settings.text(DictationKey.downloadModelFirst), .danger)
            return
        }
        token = UUID()
        let current = token
        phase = .starting
        finishWhenStarted = false
        self.target = target
        audioDucker.begin()
        startTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await capture.start(microphoneID: settings.dictationMicrophone)
                guard token == current, settings.dictationEnabled else {
                    _ = await capture.stop()
                    return
                }
                phase = .listening
                panel.language = settings.language
                panel.show()
                if finishWhenStarted { accept() }
            } catch let failure as DictationCapture.Failure {
                guard token == current else { return }
                reset()
                showMessage(failure.message(settings.language), .danger)
            } catch {
                guard token == current else { return }
                reset()
                showMessage(error.localizedDescription, .danger)
            }
        }
    }

    /// 松开按键：按住说话模式下结束本次听写。
    func released() {
        guard settings.dictationMode == .pushToTalk else { return }
        if phase == .starting { finishWhenStarted = true }
        if phase == .listening { accept() }
    }

    /// 接受当前录音：停止采集、执行转录并按目标方式插入文本。
    func accept() {
        guard phase == .listening else { return }
        phase = .transcribing
        panel.state.phase = .transcribing
        field?.isTranscribing = true
        audioDucker.end()
        let current = token
        let model = settings.dictationModel
        let language = settings.dictationLanguage
        transcriptionTask = Task { [weak self] in
            guard let self else { return }
            let samples = await capture.stop()
            guard token == current else { return }
            guard samples.count >= 1_600 else {
                reset(cancelTranscription: false)
                showMessage(settings.text(DictationKey.noSpeechRecorded), .danger)
                return
            }
            do {
                let transcript = try await models.transcribe(
                    samples, model: model,
                    language: language)
                guard token == current else { return }
                // 麦克风按钮属于其输入框：文本只插入该处，不写入剪贴板。
                let destination = field == nil ? settings.dictationDestination : .paste
                let context = destination.pastes ? DictationInsertionContext.read(in: target) : nil
                let text = DictationTextFormatter.format(
                    transcript, context: context,
                    adaptCapitalization: settings.dictationAdaptsCapitalization)
                let target = self.target
                guard !text.isEmpty else { reset(cancelTranscription: false); return }
                panel.close()
                if destination.pastes {
                    injector.deliver(
                        InjectedText(text), target: target, expectedKeyword: nil,
                        keywordLength: 0, automaticGeneration: nil,
                        isValid: { [weak self] in self?.token == current },
                        onDelivered: { [weak self] in
                            guard let self, token == current else { return }
                            if destination.copies { Paster.copyPlainText(text) }
                            reset(cancelTranscription: false)
                        },
                        onFailed: { [weak self] in
                            guard let self, token == current else { return }
                            reset(cancelTranscription: false)
                            if destination.copies { Paster.copyPlainText(text) }
                            showMessage(settings.text(DictationKey.pasteFailed), .danger)
                        })
                } else {
                    Paster.copyPlainText(text)
                    reset(cancelTranscription: false)
                }
            } catch {
                guard token == current else { return }
                reset(cancelTranscription: false)
                showMessage(error.localizedDescription, .danger)
            }
        }
    }

    /// 输入框内取消：仅当该输入框是当前会话目标时生效。
    func cancel(in editor: any InjectableTextView) {
        guard let target = target?.ownEditor, target === editor else { return }
        cancel()
    }

    /// 取消当前听写并等待采集/转录任务收敛后回到 idle。
    func cancel() {
        guard phase != .stopping, phase != .idle || !settings.dictationEnabled else { return }
        let pendingStart = startTask
        let pendingTranscription = transcriptionTask
        reset()
        phase = .stopping
        let current = token
        stopTask = Task { [weak self] in
            guard let self else { return }
            await pendingStart?.value
            _ = await capture.stop()
            await pendingTranscription?.value
            if !settings.dictationEnabled { await models.stop() }
            if token == current { phase = .idle; stopTask = nil }
        }
    }

    /// 应用退出前停掉待办任务、恢复音量并释放模型。
    func prepareForTermination() {
        enableTask?.cancel()
        cancel()
        audioDucker.restoreImmediately()
        models.prepareForTermination()
    }

    /// 复位到 idle：失效 token、取消转录、清空目标与面板状态。
    private func reset(cancelTranscription: Bool = true) {
        token = UUID()
        if cancelTranscription { transcriptionTask?.cancel() }
        startTask = nil
        transcriptionTask = nil
        phase = .idle
        target = nil
        field = nil
        panel.close()
        audioDucker.end()
    }
}

/// 记录某次麦克风会话所属的输入框，使只有该输入框显示进行中状态。
struct DictationField: Equatable {
    let editor: ObjectIdentifier
    var isTranscribing = false
}
