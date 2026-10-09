// 文件职责：在根搜索中为自定义命令提供 inline 参数输入框，并按字段收集用户填写的取值。
// 分层：UI（Launcher）；@MainActor，字段按 `$n` 位置标识而非按名称标识。
import SwiftUI

/// 自定义命令在根搜索中的 inline 输入框，按 `$n` 而非名称标识字段。
@MainActor
enum CustomCommandArgumentsAccessory {
    /// 不接受参数的命令返回 nil。
    static func make(
        command: CustomCommand?,
        vm: PaletteState,
        metrics: InterfaceMetrics,
        focus: FocusState<String?>.Binding,
        onSubmit: @escaping () -> Void
    ) -> PaletteHeaderAccessory? {
        guard let command, !command.arguments.isEmpty else { return nil }
        let arguments = command.arguments.enumerated().map { index, argument in
            InlineArgument(
                id: CustomCommandArgument.fieldID(at: index), title: argument.name,
                isOptional: argument.isOptional)
        }
        let value = { (id: String) in binding(command: command, id: id, vm: vm) }
        let firstOwed = {
            arguments.first { !$0.isOptional && value($0.id).wrappedValue.isEmpty }?.id
        }
        return PaletteHeaderAccessory(
            width: InlineArgumentFields.totalWidth(for: arguments, hasIcon: true, metrics: metrics),
            fieldNames: arguments.map(\.id),
            firstIncompleteField: firstOwed(),
            // 每行独立的 identity，使「哪些字段尚未填写」在新一行开始时重新计算。
            view: AnyView(
                InlineArgumentFields(
                    arguments: arguments, symbol: command.symbol, value: value, focused: focus,
                    openOptions: { _ in },
                    // 沿用 Raycast 的规则：↵ 不会在参数不全时执行，而是跳到必填字段。
                    onSubmit: {
                        guard let owed = firstOwed() else { return onSubmit() }
                        focus.wrappedValue = owed
                    }
                )
                .id(command.entryID))
        )
    }

    /// 按字段收集已填写的取值（已去除空值），交给运行入口使用。
    static func values(for command: CustomCommand, vm: PaletteState) -> [String: String] {
        var values: [String: String] = [:]
        for index in command.arguments.indices {
            let id = CustomCommandArgument.fieldID(at: index)
            let typed = vm.commandArguments[PaletteState.argumentKey(command.entryID, id)] ?? ""
            if !typed.isEmpty { values[id] = typed }
        }
        return values
    }

    /// 把某个字段的取值与 `PaletteState` 中的存储双向绑定。
    private static func binding(
        command: CustomCommand, id: String, vm: PaletteState
    ) -> Binding<String> {
        let key = PaletteState.argumentKey(command.entryID, id)
        return Binding(get: { vm.commandArguments[key] ?? "" }, set: { vm.commandArguments[key] = $0 })
    }
}
