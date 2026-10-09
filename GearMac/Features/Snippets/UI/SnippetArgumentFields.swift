// 文件职责：片段参数输入控件：为每个自由参数渲染一个输入框，为每个选项列表渲染一组选项 chip。
// 分层：UI；仅操作传入的 SnippetArgumentsState，不产生任何副作用。
import SwiftUI

/// 片段仍需要的 `{argument}` 取值；引用语义让调用方可以读回填写结果。
@MainActor
@Observable
final class SnippetArgumentsState {
    let arguments: [SnippetTemplateEngine.MissingArgument]
    var values: [String: String]

    init(arguments: [SnippetTemplateEngine.MissingArgument]) {
        self.arguments = arguments
        // 选项列表没有空状态，因此初始选中第一项。
        values = arguments.reduce(into: [:]) { values, argument in
            values[argument.name] = argument.options.first ?? ""
        }
    }
}

/// 片段参数对话框的控件：每个自由参数一个输入框，每个选项列表一组 chip。
struct SnippetArgumentFields: View {
    @Environment(\.metrics) private var metrics
    let state: SnippetArgumentsState

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.xl) {
            ForEach(state.arguments, id: \.name) { argument in
                VStack(alignment: .leading, spacing: metrics.spacing.sm) {
                    Text(argument.name)
                        .font(metrics.typography.rowTrailing)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    if argument.options.isEmpty {
                        TextField(
                            "", text: value(for: argument.name),
                            prompt: Text(argument.name)
                        )
                        .dialogTextField()
                    } else {
                        OptionChips(
                            options: argument.options,
                            selection: value(for: argument.name))
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Snippet argument \(argument.name)")
            }
        }
    }

    /// 为指定参数名构造读写 state.values 的绑定。
    private func value(for name: String) -> Binding<String> {
        Binding(get: { state.values[name] ?? "" }, set: { state.values[name] = $0 })
    }
}

/// 一组互斥的选项 chip，用于有预设取值的参数。
private struct OptionChips: View {
    @Environment(\.metrics) private var metrics
    let options: [String]
    @Binding var selection: String

    var body: some View {
        // 单行放不下的列表改为纵向堆叠，避免超出对话框边界。
        ViewThatFits(in: .horizontal) {
            HStack(spacing: metrics.spacing.md) { chips }
            VStack(alignment: .leading, spacing: metrics.spacing.md) { chips }
        }
    }

    /// 使用下标遍历，因为 `options=` 列表允许出现重复值。
    private var chips: some View {
        ForEach(options.indices, id: \.self) { index in
            DialogChip(title: options[index], selected: options[index] == selection) {
                selection = options[index]
            }
        }
    }
}
