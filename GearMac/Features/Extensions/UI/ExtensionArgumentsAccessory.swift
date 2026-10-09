// 文件职责：为 Palette 头部构建内联参数输入条（PaletteHeaderAccessory），仅在扩展命令声明了参数时提供。
// 分层：UI/Coordinator；不读取 Palette 内部状态，仅根据扩展命令的参数声明组装视图。
import SwiftUI

/// 内联参数条，以 `PaletteHeaderAccessory` 形式提供，Palette 无需读取其内部即可渲染。
@MainActor
enum ExtensionArgumentsAccessory {
    /// 当该行未声明参数时返回 nil——除扩展命令外，其他所有行都属于这种情况。
    static func make(
        entry: AppEntry?,
        coordinator: ExtensionCoordinator,
        values: @escaping (String) -> Binding<String>,
        focus: FocusState<String?>.Binding,
        metrics: InterfaceMetrics,
        onSubmit: @escaping () -> Void
    ) -> PaletteHeaderAccessory? {
        guard let entry, let arguments = coordinator.commandArguments(for: entry),
            !arguments.isEmpty
        else { return nil }

        let icon = entry.iconSource
        return PaletteHeaderAccessory(
            width: CommandArgumentsRow.totalWidth(for: arguments, hasIcon: true, metrics: metrics),
            fieldNames: arguments.map(\.name),
            firstIncompleteField: arguments.first {
                $0.required && values($0.name).wrappedValue.isEmpty
            }?.name,
            view: AnyView(
                CommandArgumentsRow(
                    arguments: arguments, icon: icon, value: values, focused: focus,
                    onSubmit: onSubmit)))
    }
}
