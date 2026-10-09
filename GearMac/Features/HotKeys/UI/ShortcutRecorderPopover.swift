// 文件职责：绘制录制控件的 callout（提示按键、当前按住状态或冲突信息），并把录制控件锚点提升到滚动容器之外绘制。
// 分层：UI（SwiftUI）；callout 不接收点击，交互仍由 ShortcutCaptureSession 的本地监视器处理。
import SwiftUI

/// 打开中的录制控件的边界，使 `ScrollView` 之外的祖先视图也能绘制 callout。
struct ShortcutRecorderAnchorKey: PreferenceKey {
    /// 未设置锚点时的默认值。
    static let defaultValue: Anchor<CGRect>? = nil

    /// 合并多个锚点偏好值：保留第一个非空值。
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// 输入框上方的 callout：提示该按什么、当前按住了什么，或哪里发生冲突。
struct ShortcutRecorderPopover: View {
    let placement: CalloutPlacement

    @Environment(HotKeyManager.self) private var hotKeys
    private var capture: ShortcutCaptureSession { hotKeys.capture }

    /// callout 当前要展示的按键与文案。
    private struct State {
        let caps: [String]
        let label: String
        var isExample = false
        var tint: Color?
        var prefix: String?

        /// 依据绑定构造展示状态（不标记为示例）。
        @MainActor static func binding(
            _ binding: HotKeyBinding, label: String, tint: Color? = nil
        )
            -> Self
        {
            Self(
                caps: binding.recorderKeycaps, label: label, tint: tint,
                prefix: binding.recorderPrefix)
        }
    }

    var body: some View {
        let state = self.state
        VStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(Array(state.caps.enumerated()), id: \.offset) { _, cap in
                    KeyCapChip(text: cap, scale: .hero, prefix: state.prefix)
                }
            }
            .frame(height: Theme.Size.heroKeyCap)
            .opacity(state.isExample ? 0.5 : 1)

            Text(state.label)
                .font(Theme.Typography.compactKeyCap)
                .foregroundStyle(state.tint ?? Theme.Colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(height: Theme.Size.shortcutPopoverLine)
        }
        .offset(y: Theme.Spacing.sm + 1)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .padding(placement.caretEdge == .top ? .top : .bottom, Theme.Size.calloutCaretHeight)
        .frame(
            width: Theme.Size.shortcutPopover.width, height: Theme.Size.shortcutPopover.height
        )
        .overlay(alignment: .topLeading) {
            KeyCapChip(text: "esc", scale: .compact)
                .opacity(0.7)
                .padding(.leading, Theme.Spacing.md)
                .padding(
                    .top,
                    Theme.Spacing.sm
                        + (placement.caretEdge == .top ? Theme.Size.calloutCaretHeight : 0))
        }
        // 沿用系统玻璃材质自带的层次感（与 `PopoverMenu` 一致），不手工调阴影。
        .glassSurface(in: CalloutShape(caretEdge: placement.caretEdge, caretX: placement.caretX))
    }

    /// 依据录制会话状态推导 callout 的展示内容。
    private var state: State {
        if let conflict = capture.conflict {
            return .binding(conflict.binding, label: conflict.owner, tint: .orange)
        }
        if let key = capture.awaitingSecondModifier {
            let secondPress = capture.heldModifier == key
            return .binding(
                secondPress ? key.doubleBinding : key.singleBinding,
                label: secondPress ? "Release to record" : "Tap again for double")
        }
        if let key = capture.heldModifier {
            return .binding(key.singleBinding, label: "Release or add a key")
        }
        let flags =
            capture.heldGlobe
            ? capture.heldModifiers.union(.function) : capture.heldModifiers
        let held = KeyShortcut.collapsedModifierSymbols(
            from: flags, hyperChord: KeyShortcut.displayedHyperChord())
        guard held.isEmpty else { return State(caps: held, label: "Add a key") }
        return State(
            caps: [DoubleTapModifier.option.glyph, "A"], label: "Type a shortcut", isExample: true)
    }
}

// MARK: - Host

/// 在面板之上绘制录制控件的 callout，避免被面板的 `ScrollView` 裁剪。
private struct ShortcutRecorderPopoverHost: ViewModifier {
    @Environment(HotKeyManager.self) private var hotKeys

    func body(content: Content) -> some View {
        content.overlayPreferenceValue(ShortcutRecorderAnchorKey.self) { anchor in
            GeometryReader { proxy in
                ShortcutRecorderPopoverLayer(
                    placement: anchor.map { placement(field: proxy[$0], in: proxy.size) },
                    recordingAction: hotKeys.recordingAction)
            }
            // 仅作展示：点击会穿透交给录制会话的鼠标监视器处理并关闭。
            .allowsHitTesting(false)
        }
    }

    /// 计算 callout 在容器中的放置位置。
    private func placement(field: CGRect, in size: CGSize) -> CalloutPlacement {
        CalloutPlacement.resolve(
            field: field, container: size, size: Theme.Size.shortcutPopover,
            gap: Theme.Spacing.sm, inset: Theme.Spacing.xs,
            cornerRadius: Theme.Radius.menuPanel, caretWidth: Theme.Size.calloutCaretWidth)
    }
}

/// 在 callout 淡出动画期间保留上一次的锚点位置。
private struct ShortcutRecorderPopoverLayer: View {
    let placement: CalloutPlacement?
    let recordingAction: HotKeyAction?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var presentedPlacement: CalloutPlacement?
    @State private var isVisible = false

    var body: some View {
        Color.clear.overlay {
            if let presentedPlacement {
                ShortcutRecorderPopover(placement: presentedPlacement)
                    .scaleEffect(
                        isVisible ? 1 : 0.5, anchor: scaleAnchor(for: presentedPlacement)
                    )
                    .opacity(isVisible ? 1 : 0)
                    .position(presentedPlacement.center)
            }
        }
        .onChange(of: placement, initial: true) { _, placement in
            guard let placement, recordingAction != nil else { return }
            present(at: placement)
        }
        .onChange(of: recordingAction, initial: true) { _, recordingAction in
            if recordingAction == nil {
                withAnimation(exitAnimation) { isVisible = false }
            } else if let placement {
                present(at: placement)
            }
        }
        .task(id: isVisible) {
            guard !isVisible, presentedPlacement != nil else { return }
            if !reduceMotion {
                try? await Task.sleep(for: .seconds(Theme.Duration.exit))
            }
            guard !Task.isCancelled, !isVisible else { return }
            presentedPlacement = nil
        }
    }

    /// 入场动画（启用减少动态效果时为空）。
    private var entryAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: Theme.Duration.enter)
    }

    /// 退场动画（启用减少动态效果时为空）。
    private var exitAnimation: Animation? {
        reduceMotion ? nil : .easeIn(duration: Theme.Duration.exit)
    }

    /// 呈现 callout 到指定位置，必要时触发入场动画。
    private func present(at placement: CalloutPlacement) {
        presentedPlacement = placement
        guard !isVisible else { return }
        Task { @MainActor in
            await Task.yield()
            guard recordingAction != nil, presentedPlacement == placement else { return }
            withAnimation(entryAnimation) { isVisible = true }
        }
    }

    /// 按指针方向决定缩放动画的锚点。
    private func scaleAnchor(for placement: CalloutPlacement) -> UnitPoint {
        placement.caretEdge == .bottom ? .bottom : .top
    }
}

extension View {
    /// 为该视图内所有录制控件承载快捷键录制的 callout。
    func shortcutRecorderPopoverHost() -> some View {
        modifier(ShortcutRecorderPopoverHost())
    }
}
