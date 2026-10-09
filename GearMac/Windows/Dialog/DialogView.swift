// 文件职责：对话框的 SwiftUI 视图内容，渲染标题、消息、附件控件与按钮行。
// 分层：UI；布局宽度由 DialogController 依附件类型决定。
import SwiftUI

extension DialogTone {
    /// 只给主题图标着色；按钮配色取自 `DialogAction.Role`。
    var tint: Color {
        switch self {
        case .neutral: return .secondary
        case .success: return Theme.Colors.success
        case .danger: return Theme.Colors.destructive
        }
    }

    /// 图标底板填充色，按语气调整透明度。
    var tileFill: Color {
        switch self {
        case .neutral: return tint.opacity(0.12)
        case .success, .danger: return tint.opacity(0.18)
        }
    }
}

/// GearMac 的 Liquid Glass 对话框，除非原生控件需要更多空间，否则保持紧凑。
struct DialogView: View {
    @Environment(\.metrics) private var metrics
    let request: DialogRequest
    let width: CGFloat
    let onChoose: (Int) -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: metrics.radius.panel, style: .continuous)
        VStack(alignment: .leading, spacing: metrics.spacing.xxl) {
            VStack(alignment: .leading, spacing: metrics.spacing.xxl) {
                if let symbol = request.symbol {
                    DialogSymbol(name: symbol, tone: request.tone)
                }

                VStack(alignment: .leading, spacing: metrics.spacing.sm) {
                    Text(request.title)
                        .font(metrics.typography.panelTitle)
                    if let message = request.message {
                        Text(message)
                            .font(metrics.typography.rowTitle)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                switch request.accessory {
                case .volume(let volume): VolumeSlider(state: volume)
                case .eventDraft(let draft): EventDraftFields(state: draft)
                case .snippetArguments(let arguments): SnippetArgumentFields(state: arguments)
                case nil: EmptyView()
                }
            }
            .padding(.horizontal, metrics.spacing.xs)
            .padding(.top, metrics.spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)

            actions
        }
        .padding(metrics.spacing.dialogInset)
        .frame(width: width, alignment: .leading)
        .background(Theme.Colors.panelScrim, in: shape)
        .glassSurface(in: shape)
    }

    /// 按钮区：两个按钮时尝试单行排列，超过两个则纵向堆叠。
    @ViewBuilder private var actions: some View {
        if request.actions.count == 2 {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: metrics.spacing.md) { actionButtons(singleLine: true) }
                VStack(spacing: metrics.spacing.md) { actionButtons(singleLine: false) }
            }
        } else if request.actions.count > 2 {
            VStack(spacing: metrics.spacing.md) { actionButtons }
        } else {
            HStack(spacing: metrics.spacing.md) { actionButtons }
        }
    }

    private var actionButtons: some View {
        actionButtons(singleLine: false)
    }

    private func actionButtons(singleLine: Bool) -> some View {
        ForEach(visualOrder, id: \.self) { index in
            DialogButton(
                action: request.actions[index],
                isDefault: index == request.defaultIndex,
                keyCap: keyCap(for: index),
                singleLine: singleLine,
                onActivate: { onChoose(index) }
            )
        }
    }

    /// 水平排列的两个按钮中取消在前；垂直排列时保留调用方给出的语义顺序。
    private var visualOrder: [Int] {
        guard request.actions.count < 3 else { return Array(request.actions.indices) }
        return request.actions.indices.sorted { rank(of: $0) < rank(of: $1) }
    }

    /// 取消按钮排序权重最低（优先展示）。
    private func rank(of index: Int) -> Int {
        request.actions[index].role == .cancel ? 0 : 1
    }

    /// 只提示面板实际处理的这两个按键，避免提示与实际行为脱节。
    private func keyCap(for index: Int) -> String? {
        if index == request.defaultIndex { return "↵" }
        if index == request.cancelIndex { return "⎋" }
        return nil
    }
}

/// 对话框左上角的主题图标及其底板。
private struct DialogSymbol: View {
    @Environment(\.metrics) private var metrics
    let name: String
    let tone: DialogTone

    var body: some View {
        SymbolImage(name: name, size: metrics.size.dialogSymbol, monochrome: true)
            .foregroundStyle(symbolTint)
            .frame(
                width: metrics.size.dialogSymbolContainer,
                height: metrics.size.dialogSymbolContainer
            )
            .background(
                RoundedRectangle(cornerRadius: metrics.radius.dialogSymbol, style: .continuous)
                    .fill(tone.tileFill))
    }

    /// 中性图标需要与键帽符号同等的可读性；语义色保持原样。
    private var symbolTint: Color {
        tone == .neutral ? Theme.Colors.textSecondary : tone.tint
    }
}

/// 对话框底部的一个操作按钮。
private struct DialogButton: View {
    let action: DialogAction
    let isDefault: Bool
    let keyCap: String?
    var singleLine = false
    let onActivate: () -> Void

    var body: some View {
        Button(action: onActivate) {
            Text(action.title)
                .fixedSize(horizontal: singleLine, vertical: false)
                .multilineTextAlignment(.center)
        }
        .buttonStyle(.modalAction(role))
        .tooltip(keyCap: keyCap)
    }

    /// 依据是否为默认按钮及按钮角色推导出渲染样式。
    private var role: ModalActionButtonStyle.Role {
        if isDefault, action.role == .standard { return .primary }
        return switch action.role {
        case .standard: .standard
        case .destructive: .destructive
        case .cancel: .cancel
        }
    }
}
