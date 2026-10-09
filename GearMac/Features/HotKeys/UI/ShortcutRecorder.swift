// 文件职责：提供快捷键录制控件：展示当前绑定的键帽、进入录制态并挂载捕获会话，未绑定时显示录入提示。
// 分层：UI（SwiftUI View）；刻意不可获得焦点，按键全部由 ShortcutCaptureSession 的本地监视器接管。
import AppKit
import SwiftUI

/// 刻意做成不可获得焦点的控件。参见 docs/features/hotkeys.md#recorder。
struct ShortcutRecorder: View {
    let action: HotKeyAction
    /// 去掉空槽位的填充色：一整列相同的小胶囊会比各行本身更抢眼。
    var isQuiet = false

    @Environment(HotKeyManager.self) private var hotKeys
    /// 参与观察，使纯修饰键绑定在授权状态变化时能显示警告。
    private var modifierTapMonitor: ModifierTapMonitor { hotKeys.modifierTapMonitor }
    @State private var hovered = false

    /// 本控件当前是否处于录制状态。
    private var isRecording: Bool { hotKeys.recordingAction == action }

    /// 悬停前颜色更淡，但仍不至于看起来像不可点击。
    private var unsetInk: Color {
        isRecording || !isQuiet || hovered
            ? Theme.Colors.textSecondary : Theme.Colors.textTertiary
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
        // 无论是否显示填充都保留宽度，使整列录制器填入后仍保持对齐。
        let showsFill = !isQuiet || isRecording || hovered || hotKeys.binding(for: action) != nil
        content
            .padding(.horizontal, Theme.Spacing.sm + 1)
            .frame(width: Theme.Size.shortcutRecorder, height: 24)
            .background(shape.fill(Theme.Colors.cardFill).opacity(showsFill ? 1 : 0))
            .background {
                if isRecording { ShortcutRecorderHitRegion(capture: hotKeys.capture) }
            }
            .overlay(shape.strokeBorder(Theme.Colors.cardStroke, lineWidth: 1))
            // 过长的绑定会截断，而不会改变输入框尺寸。
            .clipShape(shape)
            .contentShape(shape)
            .onTapGesture { hotKeys.recordingAction = isRecording ? nil : action }
            .onHover { hovered = $0 }
            // 当本控件是当前打开的录制器时，把它的 bounds 交给 callout。
            .anchorPreference(key: ShortcutRecorderAnchorKey.self, value: .bounds) {
                isRecording ? $0 : nil
            }
            // 行是懒加载的：滚出屏幕的录制行必须释放录制会话。
            .onDisappear { if isRecording { hotKeys.recordingAction = nil } }
            // 复用的表格行可能在旧动作仍在录制时把另一个动作交给本控件。
            .onChange(of: action) { old, _ in
                if hotKeys.recordingAction == old { hotKeys.recordingAction = nil }
            }
            .animation(.easeOut(duration: 0.12), value: hovered)
    }

    /// 内容视图：已绑定则显示键帽，否则显示录入提示。
    @ViewBuilder
    private var content: some View {
        if let binding = hotKeys.binding(for: action) {
            boundLabel(binding)
        } else {
            Text(isRecording ? "Listening…" : "Record Hotkey")
                .font(Theme.Typography.keyCap)
                .foregroundStyle(unsetInk)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 已绑定状态下展示键帽、未授权警告与清除按钮。
    private func boundLabel(_ binding: HotKeyBinding) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            // 纯修饰键绑定在未授权时无法生效，因此在绑定所在处提示。
            if binding.usesModifierTapMonitor, modifierTapMonitor.needsAccessibility {
                Button {
                    Permissions.openAccessibilitySettings()
                } label: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open Accessibility settings")
                .help("Modifier-only hotkeys need Accessibility access. Click to grant it.")
            }
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(Array(binding.recorderKeycaps.enumerated()), id: \.offset) { _, cap in
                    KeyCapChip.Label(text: cap, prefix: binding.recorderPrefix)
                        .font(Theme.Typography.keyCap)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Theme.Spacing.xs)
                        .frame(
                            minWidth: Theme.Size.recorderKeyCap, minHeight: Theme.Size.recorderKeyCap
                        )
                        .background(
                            RoundedRectangle(
                                cornerRadius: Theme.Radius.recorderKeyCap, style: .continuous
                            )
                            .fill(Color.primary.opacity(0.08))
                        )
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(binding.keycaps.joined(separator: " "))
        }
        .frame(maxWidth: .infinity)
        // 以 overlay 方式而非作为行成员，因此不会占用键帽的宽度。
        .overlay(alignment: .trailing) {
            Button {
                hotKeys.setBinding(nil, for: action)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .opacity(hovered ? 1 : 0)
            .allowsHitTesting(hovered)
        }
    }
}

/// 覆盖在录制控件上的透明 AppKit 视图，用于向捕获会话标记录制区域。
private struct ShortcutRecorderHitRegion: NSViewRepresentable {
    let capture: ShortcutCaptureSession

    /// 创建被动视图并注册为当前录制区域。
    func makeNSView(context: Context) -> PassiveView {
        let view = PassiveView()
        view.capture = capture
        capture.setActiveRecorderView(view)
        return view
    }

    /// 保持录制区域指向最新视图。
    func updateNSView(_ view: PassiveView, context: Context) {
        if view.capture !== capture { view.capture?.clearActiveRecorderView(view) }
        view.capture = capture
        capture.setActiveRecorderView(view)
    }

    /// 视图销毁时解除录制区域注册。
    static func dismantleNSView(_ view: PassiveView, coordinator: ()) {
        view.capture?.clearActiveRecorderView(view)
    }

    /// 不参与命中测试的透明 NSView。
    final class PassiveView: NSView {
        weak var capture: ShortcutCaptureSession?

        /// 永不参与命中测试，使点击穿透到 SwiftUI 层。
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
