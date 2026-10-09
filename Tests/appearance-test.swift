// 文件职责：验证主题色（Theme.Colors）在浅色/深色外观下解析正确：深色分支等于强制深色构建时期的字面量、每个表面 token 都会随外观变化，以及 AppAppearance 到 NSAppearance 的映射。
// 分层：测试 harness（无 XCTest，直接用 `swiftc` 编译）；依赖 AppKit 的实际绘制外观，失败累计后以退出码 1 结束。
import AppKit
import SwiftUI

/// 锁定 `AGENTS.md` 的约定：token 的深色分支就是强制深色构建时实际发出的字面量。
@main
@MainActor
struct AppearanceTests {
    static var failures = 0
    static var passes = 0

    /// 断言辅助：成立计入通过数，否则打印 FAIL（可带详情）并计入失败数。
    static func check(_ label: String, _ ok: Bool, _ detail: String = "") {
        if ok {
            passes += 1
        } else {
            failures += 1
            print("FAIL  \(label)\(detail.isEmpty ? "" : ": \(detail)")")
        }
    }

    /// 量化到真正进入帧缓冲的 8 位：`CGFloat` 会携带 Float 误差。
    static func components(_ color: Color, _ name: NSAppearance.Name) -> [Int] {
        var out: [Int] = []
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
            let ns = NSColor(color).usingColorSpace(.sRGB)!
            out = [ns.redComponent, ns.greenComponent, ns.blueComponent, ns.alphaComponent]
                .map { Int(($0 * 255).rounded()) }
        }
        return out
    }

    /// 断言某个 token 在深色外观下解析出的分量与期望颜色一致。
    static func dark(_ label: String, _ token: Color, is expected: Color) {
        let actual = components(token, .darkAqua)
        let wanted = components(expected, .darkAqua)
        check("dark \(label)", actual == wanted, "\(actual) != \(wanted)")
    }

    /// 浅色与深色解析结果相同的 token 从未真正做过外观适配。
    static func adapts(_ label: String, _ token: Color) {
        check(
            "\(label) adapts", components(token, .darkAqua) != components(token, .aqua),
            "light resolves identically to dark")
    }

    /// harness 入口：逐组断言深色字面量、token 自适应、scrim 反转与 AppAppearance 映射。
    static func main() {
        let c = Theme.Colors.self

        print("# dark branches are the shipped literals")
        dark("panelScrim", c.panelScrim, is: Color.black.opacity(0.4))
        dark("dialogDimming", c.dialogDimming, is: Color.black.opacity(0.34))
        dark("tooltipShadow", c.tooltipShadow, is: Color.black.opacity(0.18))
        dark("selection", c.selection, is: Color.white.opacity(0.10))
        dark("rowHover", c.rowHover, is: Color.white.opacity(0.05))
        dark("menuHover", c.menuHover, is: Color.white.opacity(0.10))
        dark("separator", c.separator, is: Color.white.opacity(0.10))
        dark("controlSurface", c.controlSurface, is: Color.white.opacity(0.10))
        dark("border", c.border, is: Color.white.opacity(0.20))
        dark("textSecondary", c.textSecondary, is: Color.white.opacity(0.60))
        dark("textTertiary", c.textTertiary, is: Color.white.opacity(0.40))
        dark("noteText", c.noteText, is: Color.white.opacity(0.90))
        dark("cardFill", c.cardFill, is: Color.white.opacity(0.05))
        dark("cardStroke", c.cardStroke, is: Color.white.opacity(0.10))
        dark("dropGuide", c.dropGuide, is: Color.white.opacity(0.35))
        dark("brand", c.brand, is: Color(red: 0.525, green: 0.231, blue: 1.0))

        print("# tokens that absorbed a literal duplicated across views")
        dark("iconPlaceholder", c.iconPlaceholder, is: Color.white.opacity(0.06))
        dark("sheen", c.sheen, is: Color.white.opacity(0.04))
        dark("textPrimary", c.textPrimary, is: Color.white)
        // VolumeHUDView 画的是 white 0.85；textPrimary 的 alpha 为 1，因此必须靠 opacity 复现它。
        dark("textPrimary at 0.85", c.textPrimary.opacity(0.85), is: Color.white.opacity(0.85))

        print("# every surface token resolves per appearance")
        for (label, token) in [
            ("panelScrim", c.panelScrim), ("selection", c.selection), ("rowHover", c.rowHover),
            ("menuHover", c.menuHover), ("separator", c.separator),
            ("controlSurface", c.controlSurface), ("border", c.border),
            ("textPrimary", c.textPrimary), ("textSecondary", c.textSecondary),
            ("textTertiary", c.textTertiary), ("noteText", c.noteText), ("cardFill", c.cardFill),
            ("cardStroke", c.cardStroke), ("dropGuide", c.dropGuide),
            ("iconPlaceholder", c.iconPlaceholder), ("sheen", c.sheen)
        ] {
            adapts(label, token)
        }

        print("# the scrim inverts rather than ramping: it lightens the light surface")
        check("light scrim is white", components(c.panelScrim, .aqua)[0] == 255)
        check("dark scrim is black", components(c.panelScrim, .darkAqua)[0] == 0)

        print("# .system hands the choice back to AppKit")
        check("system is nil", AppAppearance.system.nsAppearance == nil)
        check("light is aqua", AppAppearance.light.nsAppearance?.isDark == false)
        check("dark is darkAqua", AppAppearance.dark.nsAppearance?.isDark == true)
        check("an unknown stored value is rejected", AppAppearance(rawValue: "sepia") == nil)

        print("\n\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
