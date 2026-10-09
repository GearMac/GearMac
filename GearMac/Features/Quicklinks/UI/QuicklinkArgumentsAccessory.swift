// 文件职责：为选中快捷链接构建内联参数输入条，并以 `PaletteHeaderAccessory` 形式交给命令面板渲染。
// 分层：UI；本身不持有状态，参数值统一读写 `PaletteState.commandArguments`，须在 MainActor 上访问。
import SwiftUI

/// 内联参数条，以 `PaletteHeaderAccessory` 的形式交给命令面板渲染，面板无需理解其内部结构。
@MainActor
enum QuicklinkArgumentsAccessory {
    /// 当选中项不需要任何参数（即不含占位符的链接）时返回 nil。
    static func make(
        quicklink: Quicklink?,
        core: AppCore,
        vm: PaletteState,
        focus: FocusState<String?>.Binding,
        placement: PaletteHeaderAccessory.Placement,
        onOpenOptions: @escaping (String) -> Void,
        onSubmit: @escaping () -> Void
    ) -> PaletteHeaderAccessory? {
        guard let quicklink else { return nil }
        let metrics = core.settings.interfaceSize.metrics
        let arguments = core.quicklinkCoordinator.promptedArguments(for: quicklink).map {
            InlineArgument(
                id: $0.name, title: $0.name, options: $0.options, isOptional: $0.isOptional)
        }
        guard !arguments.isEmpty else { return nil }

        // 该行所在页面已经展示了它自己的图标，字段里再放一次会重复。
        let symbol = placement == .afterQuery ? quicklink.symbol : nil
        let value = { (name: String) in binding(quicklink: quicklink, name: name, vm: vm) }
        let pendingSelection = vm.pendingArgumentEntryID == quicklink.entryID
        return PaletteHeaderAccessory(
            width: InlineArgumentFields.totalWidth(
                for: arguments, hasIcon: symbol != nil, metrics: metrics),
            fieldNames: arguments.map(\.id),
            firstIncompleteField: arguments.first {
                (!$0.isOptional
                    || (pendingSelection && $0.id == QuicklinkCoordinator.selectionArgument.name))
                    && value($0.id).wrappedValue.isEmpty
            }?.id,
            optionsMenu: { id in
                guard let argument = arguments.first(where: { $0.id == id }),
                    !argument.options.isEmpty
                else { return nil }
                return menu(for: argument, value: value(id))
            },
            placement: placement,
            // 按行区分身份，这样「哪些字段尚未填写」在切换到下一行时会重新开始。
            view: AnyView(
                InlineArgumentFields(
                    arguments: arguments, symbol: symbol, value: value, focused: focus,
                    openOptions: onOpenOptions, onSubmit: onSubmit
                )
                .id(quicklink.entryID))
        )
    }

    /// 某个快捷链接已输入的非空参数值，也就是交给打开流程的那份字典。
    static func values(for quicklink: Quicklink, core: AppCore, vm: PaletteState) -> [String: String] {
        var values: [String: String] = [:]
        for argument in core.quicklinkCoordinator.promptedArguments(for: quicklink) {
            let typed =
                vm.commandArguments[
                    PaletteState.argumentKey(quicklink.entryID, argument.name)] ?? ""
            if !typed.isEmpty { values[argument.name] = typed }
        }
        return values
    }

    /// 把 `vm.commandArguments` 中该快捷链接某个参数的读写封装成 `Binding<String>`。
    private static func binding(
        quicklink: Quicklink, name: String, vm: PaletteState
    ) -> Binding<String> {
        let key = PaletteState.argumentKey(quicklink.entryID, name)
        return Binding(get: { vm.commandArguments[key] ?? "" }, set: { vm.commandArguments[key] = $0 })
    }

    /// 为该参数的候选值生成下拉菜单，当前选中项带勾选标记。
    private static func menu(
        for argument: InlineArgument, value: Binding<String>
    ) -> PopoverMenuContent {
        PopoverMenuContent(
            header: argument.title,
            items: argument.options.map { option in
                PopoverMenuItem(
                    title: option,
                    icon: value.wrappedValue == option ? .symbol("checkmark") : .blank
                ) {
                    value.wrappedValue = option
                }
            })
    }
}
