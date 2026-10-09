// 文件职责：用 NSImageView 播放多帧 NSImage（GIF 等），并提供判断 NSImage 是否为动画的方法。
// 分层：UI；仅做 SwiftUI 与 AppKit 的视图桥接，不改动图像数据。
import AppKit
import SwiftUI

/// 播放多帧 `NSImage`。帧计时器由 `NSImageView` 负责，SwiftUI 没有等价实现。
struct AnimatedImageView: NSViewRepresentable {
    let image: NSImage

    /// 创建配置好的 `NSImageView`，开启动画，并将两个轴的尺寸优先级设为低。
    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.animates = true
        // 两个轴都不能决定固有尺寸：否则较大的 GIF 会撑宽所在的行。
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.image = image
        return view
    }

    /// 仅在图像对象发生变化时更新视图的图像，并保持动画开启。
    func updateNSView(_ view: NSImageView, context: Context) {
        guard view.image !== image else { return }
        view.image = image
        view.animates = true
    }
}

extension NSImage {
    /// 当任一图像表示包含多于一帧时为 true——这是值得付出计时器开销的唯一情形。
    var isAnimated: Bool {
        representations.contains(where: { rep in
            guard let bitmap = rep as? NSBitmapImageRep,
                let frames = bitmap.value(forProperty: .frameCount) as? NSNumber
            else { return false }
            return frames.intValue > 1
        })
    }
}
