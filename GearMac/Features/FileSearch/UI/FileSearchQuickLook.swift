// 文件职责：面板内的 Quick Look 浮层：用卡片展示文件本体并提供关闭按钮。
// 分层：UI；SwiftUI 视图，仅负责绘制与回调关闭。
import SwiftUI

/// 面板内的 Quick Look：系统预览窗口会夺取键盘焦点并导致面板关闭。
struct FileSearchQuickLook: View {

    @Environment(\.metrics) private var metrics
    @Environment(AppSettings.self) private var settings
    let result: FileSearchResult
    let onClose: () -> Void

    /// 同心圆角：面板内每个圆角都等于外侧圆角减去对应内边距。
    private var cardRadius: CGFloat { metrics.radius.panel - metrics.spacing.md }
    private var surfaceRadius: CGFloat { cardRadius - metrics.spacing.md }

    var body: some View {
        ZStack {
            // 只有边缘区域点击关闭：预览之上的点击属于它自己的播放控制。
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)
            card
        }
    }

    /// 浮层主体卡片：预览区加上底部的文件名与关闭按钮。
    private var card: some View {
        VStack(spacing: metrics.spacing.md) {
            surface
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: metrics.spacing.sm) {
                Text(result.name)
                    .font(metrics.typography.rowTitle)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: metrics.spacing.lg)
                BarButton(action: onClose) {
                    HStack(spacing: metrics.spacing.sm) {
                        Text(settings.text(FileSearchKey.quickLookClose))
                            .font(metrics.typography.bar)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        KeyCapChip(text: "esc", style: .outline)
                    }
                }
            }
        }
        .padding(metrics.spacing.md)
        .frosted(in: RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
        .padding(metrics.spacing.md)
    }

    /// 实际展示文件的预览区（自动播放）。
    private var surface: some View {
        FileSearchSurface(url: result.url, autoplays: true)
            .clipShape(RoundedRectangle(cornerRadius: surfaceRadius, style: .continuous))
    }
}
