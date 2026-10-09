// 文件职责：自定义窗口尺寸的新增/编辑面板，编辑名称、宽高（含单位切换）、偏移量与锚点，并交给 Coordinator 保存。
// 分层：UI（SwiftUI 设置面板）；自身不持有存储，保存与删除都经 CustomWindowSizeCoordinator。
import AppKit
import SwiftUI

/// 标识要唤起的编辑器；nil 表示“新建”，UUID 用于区分两次打开互不混淆。
struct CustomWindowSizeEditRequest: Identifiable {
    let id = UUID()
    var size: CustomWindowSize?
}

/// 单个自定义尺寸的新增/编辑面板，由窗口管理设置面板唤起。
struct CustomWindowSizeEditorPanel: View {
    private let isNew: Bool
    /// 单位切换时的换算基准；实际运行时以窗口所在显示器的可见区域为准。
    private let reference: CGSize

    @Environment(\.settingsEditorDismiss) private var dismiss
    @Environment(CustomWindowSizeCoordinator.self) private var coordinator
    @Environment(AppSettings.self) private var settings
    @State private var size: CustomWindowSize
    @State private var errorMessage: String?

    init(request: CustomWindowSizeEditRequest) {
        isNew = request.size == nil
        reference = NSScreen.main?.visibleFrame.size ?? .zero
        _size = State(initialValue: request.size ?? CustomWindowSize(name: ""))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            SettingsEditorHeader(
                title: isNew
                    ? settings.text(WindowKey.sizesNew)
                    : settings.text(WindowKey.sizeEditorEditTitle),
                subtitle: settings.text(WindowKey.sizeEditorSubtitle))

            field(settings.text(WindowKey.fieldName)) {
                TextField(settings.text(WindowKey.sizeEditorNamePlaceholder), text: $size.name)
                    .settingsEditorTextField()
            }

            field(settings.text(WindowKey.fieldSize)) {
                HStack(spacing: Theme.Spacing.lg) {
                    dimensionField(
                        label: "W", name: settings.text(WindowKey.fieldWidth),
                        dimension: $size.width,
                        available: reference.width)
                    dimensionField(
                        label: "H", name: settings.text(WindowKey.fieldHeight),
                        dimension: $size.height,
                        available: reference.height)
                }
            }

            field(settings.text(WindowKey.fieldOffset)) {
                HStack(spacing: Theme.Spacing.lg) {
                    offsetField(
                        label: "X", name: settings.text(WindowKey.fieldHorizontalOffset), value: \.x)
                    offsetField(
                        label: "Y", name: settings.text(WindowKey.fieldVerticalOffset), value: \.y)
                }
            }

            field(settings.text(WindowKey.fieldPosition)) {
                WindowLayoutPositionGrid(selection: size.anchor) { size.anchor = $0 }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(Theme.Colors.destructive)
            }

            HStack(spacing: Theme.Spacing.md) {
                Button(settings.text(WindowKey.actionCancel)) { dismiss() }
                    .buttonStyle(.modalAction(.cancel))
                    .keyboardShortcut(.cancelAction)
                Button(settings.text(WindowKey.actionSave), action: save)
                    .buttonStyle(.modalAction(.primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(Theme.Spacing.dialogInset)
        .frame(width: Theme.Size.editorSheetWidth)
        .settingsEditorPanelSurface()
    }

    private func field(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(.callout.weight(.medium))
            content()
        }
    }

    /// 宽/高输入行：数值字段加单位分段控件，切换单位时按 `available` 换算当前值。
    private func dimensionField(
        label: String, name: String, dimension: Binding<CustomWindowSize.Dimension>,
        available: CGFloat
    ) -> some View {
        let unit = dimension.wrappedValue.unit
        return HStack(spacing: Theme.Spacing.sm) {
            WindowLayoutNumberField(
                label: label, name: name, suffix: unit.suffix, range: unit.range,
                value: dimension.wrappedValue.value,
                onCommit: { dimension.wrappedValue = .init($0, unit) })
            Picker(
                String(format: settings.text(WindowKey.sizeEditorUnit), name),
                selection: Binding(
                    get: { unit },
                    set: {
                        dimension.wrappedValue = dimension.wrappedValue.converted(
                            to: $0, in: available)
                    })
            ) {
                ForEach(CustomWindowSize.Dimension.Unit.allCases, id: \.self) {
                    Text($0.suffix).tag($0)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.large)
            .buttonBorderShape(.roundedRectangle(radius: Theme.Radius.barControl))
            .fixedSize()
        }
    }

    /// 偏移输入行：按 key path 绑定到水平/垂直偏移，单位固定为 pt。
    private func offsetField(
        label: String, name: String, value: WritableKeyPath<CustomWindowSize.Offset, Int>
    ) -> some View {
        WindowLayoutNumberField(
            label: label, name: name, suffix: "pt", range: CustomWindowSize.Offset.range,
            value: size.offset[keyPath: value],
            onCommit: { size.offset[keyPath: value] = $0 })
    }

    /// 名称为空（去除首尾空白后）时禁止保存。
    private var canSave: Bool {
        !size.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 交给 Coordinator 保存并在成功后关闭面板，失败时把错误显示在面板内。
    private func save() {
        guard canSave else { return }
        do {
            try coordinator.saveCustomWindowSize(size)
            dismiss()
        } catch {
            errorMessage = error.localizedMessage(settings.resolvedLanguage)
        }
    }
}
