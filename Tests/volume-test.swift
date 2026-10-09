// 文件职责：验证 VolumeLevel 的步进、钳制、预设对齐、扬声器字形分档与百分比格式化。
// 分层：测试 harness；仅 import Foundation，对音量网格做纯数值断言。

import Foundation

/// 音量级别网格的独立契约测试 harness（直接运行，不依赖 XCTest）。
@main
@MainActor
struct VolumeLevelTests {
    static var failures = 0
    static var passes = 0

    /// 断言辅助：条件不成立时累加失败计数并打印消息。
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    /// 浮点断言辅助：容差 1e-9，失败时打印实际值与期望值。
    static func expect(_ actual: Double, _ expected: Double, _ message: String) {
        expect(abs(actual - expected) < 1e-9, "\(message) — got \(actual), want \(expected)")
    }

    /// 入口：逐项校验网格、步进、钳制、字形与百分比，失败时以退出码 1 结束。
    static func main() {
        expect(VolumeLevel.steps == 20, "the grid is 20 lines")
        expect(VolumeLevel.step, 0.05, "one step is 5%")

        expect(VolumeLevel.clamped(-0.5), 0, "below zero clamps to zero")
        expect(VolumeLevel.clamped(1.5), 1, "above one clamps to one")
        expect(VolumeLevel.clamped(0.42), 0.42, "an in-range level passes through")

        // 落在网格上的级别在两个方向上恰好移动一步。
        for line in 0...VolumeLevel.steps {
            let level = Double(line) * VolumeLevel.step
            if line < VolumeLevel.steps {
                expect(
                    VolumeLevel.stepped(level, up: true), level + VolumeLevel.step,
                    "up from \(VolumeLevel.percentage(level)) moves one step")
            }
            if line > 0 {
                expect(
                    VolumeLevel.stepped(level, up: false), level - VolumeLevel.step,
                    "down from \(VolumeLevel.percentage(level)) moves one step")
            }
        }

        // 偏离网格的级别落在行进方向上最近的刻度，绝不越过。
        expect(VolumeLevel.stepped(0.37, up: true), 0.40, "up from 37% lands on 40%")
        expect(VolumeLevel.stepped(0.37, up: false), 0.35, "down from 37% lands on 35%")
        expect(VolumeLevel.stepped(0.01, up: false), 0, "down from 1% lands on 0%")
        expect(VolumeLevel.stepped(0.99, up: true), 1, "up from 99% lands on 100%")
        expect(VolumeLevel.stepped(0.021, up: true), 0.05, "a hair above 2% still steps up to 5%")

        // 一旦落到网格上，连续按键会一直保持在网格上。
        var climbing = 0.37
        for expected in [0.40, 0.45, 0.50, 0.55] {
            climbing = VolumeLevel.stepped(climbing, up: true)
            expect(climbing, expected, "climbing from 37% reaches \(Int(expected * 100))%")
        }
        var falling = 0.37
        for expected in [0.35, 0.30, 0.25, 0.20] {
            falling = VolumeLevel.stepped(falling, up: false)
            expect(falling, expected, "falling from 37% reaches \(Int(expected * 100))%")
        }

        // 两端会吸收后续按键，而不是回绕或越界。
        expect(VolumeLevel.stepped(0, up: false), 0, "down at zero stays at zero")
        expect(VolumeLevel.stepped(1, up: true), 1, "up at full stays at full")
        expect(VolumeLevel.stepped(-1, up: false), 0, "an out-of-range low level clamps first")
        expect(VolumeLevel.stepped(2, up: true), 1, "an out-of-range high level clamps first")

        // 预设命令都落在网格上，因此在其之后步进仍是整数刻度。
        for preset in [0, 0.25, 0.5, 0.75, 1.0] {
            let line = preset * Double(VolumeLevel.steps)
            expect(
                line == line.rounded(),
                "the \(VolumeLevel.percentage(preset)) preset is on the grid")
        }

        // 扬声器字形：无论底层级别如何，静音与无声都显示为斜杠。
        expect(
            VolumeLevel.symbol(level: 0.8, muted: true) == "speaker.slash.fill", "muted is slashed")
        expect(VolumeLevel.symbol(level: 0) == "speaker.slash.fill", "silent is slashed")
        expect(VolumeLevel.symbol(level: 0.05) == "speaker.wave.1.fill", "a low level is one wave")
        expect(VolumeLevel.symbol(level: 0.5) == "speaker.wave.2.fill", "half is two waves")
        expect(VolumeLevel.symbol(level: 1) == "speaker.wave.2.fill", "full stops at two waves")
        expect(
            VolumeLevel.symbol(level: 2) == VolumeLevel.symbol(level: 1),
            "an out-of-range level clamps first")
        // 分档只升不降，因此级别上升时绝不会画出更安静的字形。
        let bands = stride(from: 0.0, through: 1.0, by: VolumeLevel.step)
            .map { VolumeLevel.symbol(level: $0) }
        expect(
            zip(bands, bands.dropFirst()).allSatisfy { $0 <= $1 },
            "the glyph never steps backwards as the level rises")
        expect(Set(bands).count == 3, "every band is reachable on the step grid")

        expect(VolumeLevel.percentage(0) == "0%", "zero reads 0%")
        expect(VolumeLevel.percentage(0.45) == "45%", "a grid level reads a round number")
        expect(VolumeLevel.percentage(1) == "100%", "full reads 100%")
        expect(VolumeLevel.percentage(1.4) == "100%", "an over-range level reads 100%")
        expect(VolumeLevel.percentage(-0.2) == "0%", "an under-range level reads 0%")
        expect(
            (0...VolumeLevel.steps).allSatisfy {
                !VolumeLevel.percentage(Double($0) * VolumeLevel.step).contains(".")
            },
            "no grid level ever reads as a fraction")

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
