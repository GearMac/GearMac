// 文件职责：渲染启动器顶部的紧凑收藏行（一排小图标与溢出按钮）。
// 分层：UI；数字快捷键与溢出规则来自 FavoriteSlots，本文件只负责布局与回调。
import SwiftUI

/// 溢出项是一个按钮而非占位槽，因此没有任何收藏会因此失去自己的数字快捷键。
struct CompactFavoritesRow: View {
    let favorites: [AppEntry]
    let showsOverflow: Bool
    let onLaunch: (AppEntry) -> Void
    let onOverflow: () -> Void
    @Environment(\.metrics) private var metrics
    @Environment(AppSettings.self) private var settings

    /// 横向排列收藏图标，末尾可选一个溢出按钮。
    var body: some View {
        HStack(spacing: metrics.spacing.xs) {
            // 以应用为标识，因此重排时图标随其应用移动，而不是按位置固定。
            ForEach(Array(favorites.enumerated()), id: \.element.id) { index, app in
                CompactFavoriteButton(help: help(for: app, at: index)) {
                    onLaunch(app)
                } content: {
                    // 与结果行相同的尺寸，使收起与展开共用同一张缓存位图。
                    AppIconView(app: app, pointSize: metrics.size.resultRowIcon)
                        .frame(width: metrics.size.rowIcon, height: metrics.size.rowIcon)
                }
            }
            if showsOverflow {
                CompactFavoriteButton(help: settings.text(LauncherKey.showAll), action: onOverflow) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(width: metrics.size.rowIcon, height: metrics.size.rowIcon)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Theme.Colors.controlSurface)
                                .padding(metrics.spacing.xxs)
                        )
                }
            }
        }
    }

    /// 生成 tooltip 文案：有数字快捷键时追加“⌘<数字>”。
    private func help(for app: AppEntry, at index: Int) -> String {
        guard let digit = FavoriteSlots.digit(at: index) else { return app.name }
        return "\(app.name)  ⌘\(digit)"
    }
}

/// 单个紧凑收藏：纯图标 + 提示 + 动作，无悬停装饰，因而显得紧凑。
private struct CompactFavoriteButton<Content: View>: View {
    let help: String
    let action: () -> Void
    @ViewBuilder let content: Content
    @Environment(\.metrics) private var metrics

    /// 以 plain 按钮样式包裹内容，并附带 tooltip。
    var body: some View {
        Button(action: action) {
            content
                .contentShape(RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
