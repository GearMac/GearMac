// 文件职责：窗口布局的新增/编辑面板，左侧实时预览、右侧属性检视器，并负责保存与错误展示。
// 分层：UI（SwiftUI 设置弹窗）；几何换算委托给 WindowLayoutDraft / WindowLayoutGeometry，保存经 windowLayoutCoordinator。
import AppKit
import SwiftUI

/// 标识要唤起的编辑器；nil 表示“新建”，UUID 用于区分两次打开互不混淆。
struct WindowLayoutEditRequest: Identifiable {
    let id = UUID()
    var layout: WindowLayout?
    /// 由“捕获当前窗口”流程置位，面板据此调整标题文案。
    var isCapture = false
}

/// 单个布局的新增/编辑面板，由窗口管理设置面板唤起。
struct WindowLayoutEditorPanel: View {
    let request: WindowLayoutEditRequest

    @Environment(\.settingsEditorDismiss) private var dismiss
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    @State private var draft: WindowLayoutDraft
    @State private var screens: [WindowLayoutScreen]
    @State private var errorMessage: String?

    /// 以当前连接的显示器初始化草稿；屏幕列表同时作为画布与页签的数据源。
    init(request: WindowLayoutEditRequest) {
        self.request = request
        let connected = Self.connectedScreens()
        _screens = State(initialValue: connected)
        _draft = State(
            initialValue: WindowLayoutDraft(
                layout: request.layout, isCapture: request.isCapture,
                displays: connected.map(\.display)))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                previewColumn
                Divider()
                WindowLayoutInspector(draft: draft, displays: screens.map(\.display))
                    .frame(width: Theme.Size.layoutInspectorColumn)
            }
            // 固定高度而非由内容撑开：否则字段出现时面板会跳动。
            .frame(height: Theme.Size.layoutEditorSheet.height)
            Divider()
            footer
        }
        .frame(width: Theme.Size.layoutEditorSheet.width)
        .settingsEditorPanelSurface()
        .task {
            // 编辑期间显示器可能被拔掉；画布不能继续绘制已失效的几何信息。
            for await _ in NotificationCenter.default.notifications(
                named: NSApplication.didChangeScreenParametersNotification)
            {
                screens = Self.connectedScreens()
            }
        }
    }

    /// 左栏：标题与实时预览。
    private var previewColumn: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Text(title)
                .font(Theme.Typography.panelTitle)
            WindowLayoutPreview(draft: draft, screens: screens, gap: previewGap)
        }
        .padding(Theme.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 读取当前连接的显示器，并转换为布局可直接使用的屏幕几何。
    private static func connectedScreens() -> [WindowLayoutScreen] {
        AXScreens.layoutScreens(geometry: AXGeometry(screens: NSScreen.screens))
    }

    /// 标题：捕获、新建、编辑三种状态各不同。
    private var title: String {
        if request.isCapture { return settings.text(WindowKey.editorCaptureTitle) }
        return request.layout == nil
            ? settings.text(WindowKey.editorNewTitle) : settings.text(WindowKey.editorEditTitle)
    }

    /// 预览用的间距：仅当勾选“使用首选间距”时取设置值，否则为 0。
    private var previewGap: CGFloat {
        draft.usesPreferredGap ? CGFloat(settings.windowGap) : 0
    }

    /// 错误显示在此处而非页脚上方，这样报错不会撑大面板高度。
    private var footer: some View {
        HStack(spacing: Theme.Spacing.xl) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Button(settings.text(WindowKey.actionCancel)) { dismiss() }
                .buttonStyle(.modalAction(.cancel, fillsWidth: false))
                .keyboardShortcut(.cancelAction)
            Button(action: save) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(settings.text(WindowKey.actionSave))
                    HStack(spacing: Theme.Spacing.xxs) {
                        KeyCapChip(text: "⌘", scale: .compact)
                        KeyCapChip(text: "↵", scale: .compact)
                    }
                }
            }
            .buttonStyle(.modalAction(.primary, fillsWidth: false))
            // 不用 `.defaultAction`：单独的 ↵ 属于当前聚焦的字段。
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!draft.canSave)
        }
        .padding(.horizontal, Theme.Spacing.xxl)
        .padding(.vertical, Theme.Spacing.xl)
    }

    /// 按草稿是否已有同名条目决定新增还是更新，成功后关闭面板。
    private func save() {
        guard draft.canSave else { return }
        let value = draft.layout()
        do {
            if draft.existingID == nil || core.windowLayouts.layout(id: value.id) == nil {
                try core.windowLayoutCoordinator.addWindowLayout(value)
            } else {
                try core.windowLayoutCoordinator.updateWindowLayout(value)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedMessage(settings.resolvedLanguage)
        }
    }
}
