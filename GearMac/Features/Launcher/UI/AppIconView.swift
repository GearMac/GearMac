// 文件职责：渲染启动器列表行的应用图标，并在后台解码图标、就绪前显示占位背景。
// 分层：UI；图标解码移出主线程，命中热缓存时同步取用因而不会闪烁。
import SwiftUI

/// 行的图标视图：在主线程之外解码；命中热缓存的图标同步取用，因此不会闪烁。
struct AppIconView: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.displayScale) private var displayScale
    let app: AppEntry
    /// 为 nil 时复用共享的 96px 位图；传入尺寸则为本行单独使用一张小得多的位图。
    var pointSize: CGFloat?
    @State private var loaded: Loaded?

    /// 图标缓存键：由图标标识与请求尺寸共同决定。
    private struct Key: Hashable {
        let icon: String
        let size: IconSize?
    }

    /// 异步加载结果：本次请求及其解码出的图片，用于判断是否仍然有效。
    private struct Loaded {
        let request: IconRequest<Key>
        let image: NSImage?
    }

    /// 优先用热缓存或已加载的图片渲染；两者都无则展示占位圆角矩形，并在 .task 中发起异步加载。
    var body: some View {
        let size = pointSize.map { IconSize(points: $0, scale: displayScale) }
        // 以图标而非条目为键：扩展重新换肤时其 `id` 并不会改变。
        let request = IconRequest(Key(icon: app.iconKey, size: size))
        let warm = IconCache.cached(app.iconSource, fileURL: app.url, size: size)
        let image = warm ?? (loaded?.request == request ? loaded?.image : nil)
        Group {
            if let image {
                Image(nsImage: image).resizable()
            } else {
                RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                    .fill(Theme.Colors.iconPlaceholder)
            }
        }
        .task(id: request) {
            guard warm == nil else { return }
            let image = await IconCache.loadAsync(app.iconSource, fileURL: app.url, size: size)
            guard !Task.isCancelled else { return }
            loaded = Loaded(request: request, image: image)
        }
    }
}
