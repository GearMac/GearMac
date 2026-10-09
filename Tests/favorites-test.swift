// 文件职责：校验收藏夹快捷键槽位（⌘1–⌘9、⌘0）的映射规则：数字、物理键码与行号三者一致。
// 分层：测试 harness；依赖 FavoriteSlots 的纯映射逻辑，不启动 UI。

import Foundation

/// 收藏夹槽位映射的独立测试 harness（直接运行，不依赖 XCTest）。
@main
struct FavoritesTest {
    /// harness 入口：内联定义 check 断言，逐项验证后打印结果并在失败时退出码 1。
    static func main() {
        var failures = 0

        func check(_ description: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(description)")
            } else {
                print("FAIL  \(description)")
                failures += 1
            }
        }

        // 十进制数字键上限就是十个：不存在 ⌘10，因此第十一个收藏无法分配快捷键。
        check("ten slots", FavoriteSlots.digits.count == 10)
        check("no digit repeats", Set(FavoriteSlots.digits).count == FavoriteSlots.digits.count)

        check("⌘1 is the first favorite", FavoriteSlots.index(for: "1") == 0)
        check("⌘9 is the ninth", FavoriteSlots.index(for: "9") == 8)
        check("⌘0 is the tenth, not the first", FavoriteSlots.index(for: "0") == 9)
        check("a letter is not a slot", FavoriteSlots.index(for: "a") == nil)

        let numberRowKeyCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29]
        for (index, keyCode) in numberRowKeyCodes.enumerated() {
            check(
                "physical number-row keycode \(keyCode) maps to slot \(index)",
                FavoriteSlots.index(forKeyCode: keyCode) == index)
        }
        check("unknown keycode is not a slot", FavoriteSlots.index(forKeyCode: 0) == nil)

        check("the first row shows 1", FavoriteSlots.digit(at: 0) == "1")
        check("the tenth row shows 0", FavoriteSlots.digit(at: 9) == "0")
        check("the eleventh row shows nothing", FavoriteSlots.digit(at: 10) == nil)
        check("a negative index shows nothing", FavoriteSlots.digit(at: -1) == nil)

        // 行内覆盖层与按键处理必须一致，否则某一行会展示出属于另一行的快捷键。
        for index in FavoriteSlots.digits.indices {
            guard let digit = FavoriteSlots.digit(at: index) else {
                check("slot \(index) has a digit", false)
                continue
            }
            check("slot \(index) round-trips", FavoriteSlots.index(for: digit) == index)
        }

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) failed")
        if failures > 0 { exit(1) }
    }
}
