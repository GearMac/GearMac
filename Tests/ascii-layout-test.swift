// 文件职责：验证非 QWERTY 布局下命名键的恢复逻辑——命名键与对照键按原始含义解析，字母键回退到布局字符。
// 分层：测试 harness；依赖 AppKit/SwiftUI，直接在主线程上断言。
import AppKit
import SwiftUI

/// `UCKeyTranslate` 会用 ASCII 测试所接受的某个控制字符来应答命名键的 keycode。
/// ASCII 布局恢复逻辑的测试入口，断言命名键不会被布局字符覆盖。
@main
@MainActor
struct ASCIILayoutTests {
    static var failures = 0
    static var passes = 0

    /// 记录一次断言：通过则计入通过数，否则打印失败标签。
    static func check(_ label: String, _ ok: Bool) {
        if ok {
            passes += 1
        } else {
            failures += 1
            print("FAIL  \(label)")
        }
    }

    /// `UCKeyTranslate` 在 ⌘ 下对每个 keycode 返回的内容，与 SwiftUI 自身的拼写对照。
    static let namedKeys: [(name: String, key: KeyEquivalent, translated: Character)] = [
        ("↑", .upArrow, "\u{1e}"),
        ("↓", .downArrow, "\u{1f}"),
        ("←", .leftArrow, "\u{1c}"),
        ("→", .rightArrow, "\u{1d}"),
        ("⌦", .deleteForward, "\u{7f}"),
        ("⇞", .pageUp, "\u{b}"),
        ("⇟", .pageDown, "\u{c}"),
        ("↖", .home, "\u{1}"),
        ("↘", .end, "\u{4}")
    ]

    /// 这几个键本就与 SwiftUI 一致，在排除方向键之后也必须继续正确解析。
    static let controlKeys: [(name: String, key: KeyEquivalent, translated: Character)] = [
        ("↩", .return, "\u{d}"),
        ("⌫", .delete, "\u{8}"),
        ("⇥", .tab, "\u{9}"),
        ("⎋", .escape, "\u{1b}"),
        ("space", .space, " ")
    ]

    /// 打印分组标题并逐组断言，最后以失败数决定退出码。
    static func main() {
        print("# a named key is never recovered from the layout")
        for entry in namedKeys {
            check(
                "\(entry.name) keeps SwiftUI's key",
                ASCIIKeyboardLayout.recovered(entry.key, layoutCharacter: entry.translated)
                    == entry.key)
        }

        print("\n# a key whose control character is already SwiftUI's still resolves")
        for entry in controlKeys {
            check(
                "\(entry.name) resolves to itself",
                ASCIIKeyboardLayout.recovered(entry.key, layoutCharacter: entry.translated)
                    == entry.key)
        }

        print("\n# the recovery still does its job")
        check(
            "a non-QWERTY layout recovers the logical key",
            ASCIIKeyboardLayout.recovered(KeyEquivalent("t"), layoutCharacter: "k")
                == KeyEquivalent("k"))
        check(
            "a non-ASCII layout character falls back to SwiftUI's key",
            ASCIIKeyboardLayout.recovered(KeyEquivalent("k"), layoutCharacter: "ц")
                == KeyEquivalent("k"))
        check(
            "no layout character falls back to SwiftUI's key",
            ASCIIKeyboardLayout.recovered(KeyEquivalent("k"), layoutCharacter: nil)
                == KeyEquivalent("k"))
        check(
            "a shifted letter is still spelled lower case",
            ASCIIKeyboardLayout.recovered(KeyEquivalent("C"), layoutCharacter: nil)
                == KeyEquivalent("c"))

        print("\n\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
