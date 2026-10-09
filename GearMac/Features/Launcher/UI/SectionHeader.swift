// 文件职责：提供所有启动器列表共用的分组标题行（可选齿轮配置按钮）。
// 分层：UI；纯展示组件，配置动作由调用方以闭包传入。
import SwiftUI

/// 位于一组行上方的分组标题，供每个启动器列表共用。
struct SectionHeader: View {
    @Environment(\.metrics) private var metrics
    let title: String
    /// 首个标题紧贴上沿；后续标题上方留出间距，读作「在其下方」。
    var isFirst = false
    /// 标题旁的齿轮按钮，用于成员由用户自行选择的分组。
    var configure: (() -> Void)?
    /// 有值时使用调用方传入的提示；否则用默认的「配置」提示。
    var configureHelp: String?
    @Environment(AppSettings.self) private var settings

    /// 渲染标题文本与可选齿轮按钮，并处理首次/非首次的上间距。
    var body: some View {
        HStack(spacing: metrics.spacing.sm) {
            Text(title)
                .lineLimit(1)
            if let configure {
                Button(action: configure) {
                    Image(systemName: "gearshape")
                        .imageScale(.small)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(configureHelp ?? settings.text(LauncherKey.sectionConfigureHelp))
            }
            Spacer(minLength: 0)
        }
        .font(metrics.typography.sectionHeader)
        .foregroundStyle(.secondary)
        .padding(.horizontal, metrics.spacing.md)
        .padding(.top, isFirst ? metrics.spacing.xs : metrics.spacing.sectionSpacing)
        .padding(.bottom, metrics.spacing.sectionHeaderBottom)
    }
}
