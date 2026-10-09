// 文件职责：听写浮层面板的 SwiftUI 视图与 NSPanel 控制器，负责波形展示、处理中动画与回车/esc 键的接受与取消。
// 分层：UI；面板相关状态与 AppKit 操作都限定在主线程，不在此文件承载听写识别逻辑。
import AppKit
import Carbon.HIToolbox
import SwiftUI

/// 听写浮层对外暴露的可观察显示状态：当前阶段与频谱柱高度。
@MainActor
@Observable
final class DictationDisplayState {
    /// 听写阶段：监听中或转写中。
    enum Phase { case listening, transcribing }
    var phase: Phase = .listening
    var levels = [Float](repeating: 0, count: DictationSpectrum.barCount)
}

/// 频谱柱波形视图，按传入的 `levels` 绘制并随音量变化。
private struct DictationWaveform: View {
    let levels: [Float]
    let processing: Bool

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.dictationWaveGap) {
            ForEach(levels.indices, id: \.self) { index in
                let emphasis =
                    processing
                    ? Double(levels[index])
                    : min(1, Double(min(index, levels.count - 1 - index)) / 3)
                Capsule()
                    .fill(Theme.Colors.textPrimary.opacity(0.4 + 0.6 * emphasis))
                    .frame(
                        width: Theme.Size.dictationWaveBar,
                        height: 3 + (processing ? 9 : 25) * CGFloat(levels[index]))
            }
        }
        .animation(.easeOut(duration: 0.06), value: levels)
    }
}

/// 转写阶段的循环推进光带动画，与真实音量无关。
private struct DictationProcessingWave: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            let progress =
                timeline.date.timeIntervalSince(startedAt)
                .truncatingRemainder(dividingBy: 1.2) / 1.2
            let center = (reduceMotion ? 0.5 : progress) * 28 - 4
            DictationWaveform(
                levels: (0..<DictationSpectrum.barCount).map { index in
                    Float(max(0, 1 - abs(Double(index) - center) / 4))
                }, processing: true)
        }
    }
}

/// 面板根视图，按 `state.phase` 在音量波形与处理中动画之间切换。
private struct DictationPanelView: View {
    let state: DictationDisplayState
    /// 无障碍标签所用的语言，由控制器在展示前写入。
    let language: AppLanguage

    var body: some View {
        Group {
            if state.phase == .listening {
                DictationWaveform(
                    levels: state.levels.enumerated().map { index, level in
                        let edge = min(1, Float(min(index, state.levels.count - 1 - index)) / 4)
                        let taper = edge * edge * (3 - 2 * edge)
                        return level * (0.2 + 0.8 * taper)
                    }, processing: false
                )
                .accessibilityLabel(
                    L10n.string(DictationKey.accessibilityListening, language: language))
            } else {
                DictationProcessingWave()
                    .accessibilityLabel(
                        L10n.string(DictationKey.accessibilityTranscribing, language: language))
            }
        }
        .frame(width: Theme.Size.dictationPanel.width, height: Theme.Size.dictationPanel.height)
        .glassSurface(in: .capsule)
    }
}

/// 无边框、非激活式浮层面板，拦截回车与 esc 键并回调接受/取消。
private final class DictationPanel: NSPanel {
    var onAccept: (() -> Void)?
    var onCancel: (() -> Void)?

    init(content: NSView) {
        super.init(
            contentRect: NSRect(origin: .zero, size: Theme.Size.dictationPanel),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        contentView = content
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    /// 面板可以成为 key window，以便接收键盘事件。
    override var canBecomeKey: Bool { true }
    /// 不需要成为 main window。
    override var canBecomeMain: Bool { false }

    /// 发送事件前先拦截回车与 esc：回车触发接受，esc 触发取消。
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, !event.isARepeat {
            switch Int(event.keyCode) {
            case kVK_Return, kVK_ANSI_KeypadEnter: onAccept?(); return
            case kVK_Escape: onCancel?(); return
            default: break
            }
        }
        super.sendEvent(event)
    }
}

/// 听写浮层面板的生命周期控制器：创建、定位到屏幕底部附近、显示与关闭。
@MainActor
final class DictationPanelController {
    let state = DictationDisplayState()
    /// 面板无障碍标签所用的语言；每次展示前由协调器更新。
    var language: AppLanguage = .system
    private var panel: DictationPanel?
    var onAccept: (() -> Void)?
    var onCancel: (() -> Void)?

    /// 将面板水平居中在屏幕底部上方约 10% 处，重置状态后置顶显示。
    func show() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }
        let panel =
            panel
            ?? DictationPanel(
                content: NSHostingView(
                    rootView: DictationPanelView(state: state, language: language)))
        panel.onAccept = onAccept
        panel.onCancel = onCancel
        self.panel = panel
        let size = Theme.Size.dictationPanel
        panel.setFrameOrigin(
            NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.minY + frame.height * 0.1 - size.height / 2))
        state.phase = .listening
        state.levels = [Float](repeating: 0, count: DictationSpectrum.barCount)
        panel.makeKeyAndOrderFront(nil)
    }

    /// 隐藏面板并释放实例。
    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}
