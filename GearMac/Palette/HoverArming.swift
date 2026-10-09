// 文件职责：判断鼠标移动是「有意选择某行」还是「无意漂移」的纯几何判定。
// 分层：Model；纯计算，导入状态由 `PaletteState` 持有，本文件不 import AppKit/SwiftUI。
import CoreGraphics

/// 判断指针移动是否属于有意选择行而非漂移；armed 状态保存在 `PaletteState` 上。
enum HoverArming {
    /// 滚轮点击会让鼠标挪动一两个点，手势结束时也可能没有位移，因此需要容差。
    private static let slop: CGFloat = 3

    /// 指针相对锚点的位移超过容差时才算有意移动。
    static func isDeliberate(_ pointer: CGPoint, from anchor: CGPoint) -> Bool {
        hypot(pointer.x - anchor.x, pointer.y - anchor.y) > slop
    }
}
