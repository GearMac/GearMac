// 文件职责：定义收藏项的快捷槽位（⌘1…⌘9、⌘0）与数字、物理按键码到槽位下标的双向换算。
// 分层：Model；不得 import AppKit/SwiftUI，仅依赖 Foundation。
import Foundation

/// ⌘1…⌘9 之后用 ⌘0 表示第十个；超出的收藏仍会列出，但不再带快捷键。
enum FavoriteSlots {
    /// 槽位对应的数字字符，顺序即槽位顺序。
    static let digits: [Character] = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]

    /// 按视觉顺序 1…9、0 排列的 ANSI 数字行键码，与键盘布局无关。
    private static let numberRowKeyCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29]

    /// 某个数字键会启动的收藏项；该键不是槽位时返回 nil。
    static func index(for digit: Character) -> Int? { digits.firstIndex(of: digit) }

    /// 某个物理数字行按键会启动的收藏项；该键不是槽位时返回 nil。
    static func index(forKeyCode keyCode: UInt16) -> Int? {
        numberRowKeyCodes.firstIndex(of: keyCode)
    }

    /// `index` 位置的行上显示的数字；超出最后一个槽位时返回 nil。
    static func digit(at index: Int) -> Character? {
        digits.indices.contains(index) ? digits[index] : nil
    }
}
