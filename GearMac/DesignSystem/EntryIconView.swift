// 文件职责：绘制 `EntryIcon` 的图标视图 `EntryIconView`，并通过 `IconCache` 同步取缓存、异步加载图标。
// 分层：UI（DesignSystem）；图标加载走 `IconCache` 服务，视图只持有 `@State` 图片，不阻塞首帧渲染。
import SwiftUI

/// 绘制 `EntryIcon`：先取缓存作为初始值，使已缓存的图标能在首帧就画出来。
struct EntryIconView: View {
    let source: EntryIcon
    /// 只有 `.file` 类型的图标需要它，并且只有启动器能提供该地址。
    var fileURL: URL = URL(fileURLWithPath: "/")
    @State private var image: NSImage?
    @Environment(\.metrics) private var metrics

    init(source: EntryIcon, fileURL: URL = URL(fileURLWithPath: "/")) {
        self.source = source
        self.fileURL = fileURL
        _image = State(initialValue: IconCache.cached(source, fileURL: fileURL))
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable()
            } else {
                RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                    .fill(Theme.Colors.iconPlaceholder)
            }
        }
        // 以图标本身（而非条目）作为标识：仅更换皮肤不会改变条目 id。
        .task(id: IconRequest(source)) {
            if let warm = IconCache.cached(source, fileURL: fileURL) {
                image = warm
                return
            }
            image = await IconCache.loadAsync(source, fileURL: fileURL)
        }
    }
}
