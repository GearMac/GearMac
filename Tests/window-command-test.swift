// 文件职责：窗口管理纯逻辑的独立契约测试——覆盖窗口几何排布（WindowPlacementEngine）、窗口命令目录与重复按键的动作记忆（WindowActionMemory）。
// 分层：测试 harness；不依赖 AppKit/SwiftUI，仅用 CoreGraphics 与 Foundation，以 @main 直接运行并统计断言通过/失败数。
import CoreGraphics
import Foundation

/// 窗口管理纯逻辑的契约测试入口：`@main` 依次运行全部测试函数，最后打印通过/失败计数，有失败则以退出码 1 结束。
@main
@MainActor
struct WindowCommandTests {
    static var failures = 0
    static var passes = 0

    /// 断言辅助：条件成立即累计通过数，否则累计失败数并打印 `FAIL: <message>`。
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    /// 断言辅助：两个 CGRect 完全相等才算通过，否则打印实际值与期望值。
    static func expectRect(_ actual: CGRect, _ expected: CGRect, _ message: String) {
        if actual == expected {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message) — got \(actual), expected \(expected)")
        }
    }

    // MARK: - Fixtures

    /// 参考显示器：原点即 AX 原点，尺寸可被二等分与三等分整除。
    static let mainScreen = WindowPlacementEngine.Screen(
        id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900))

    /// 把可变参数的屏幕列表打包成数组，便于测试里书写多显示器场景。
    static func screens(_ list: WindowPlacementEngine.Screen...) -> [WindowPlacementEngine.Screen] { list }

    /// 以默认参数组装 `WindowPlacementEngine.Input` 并调用 placement，返回完整排布结果（含目标屏幕）。
    static func placement(
        _ command: WindowCommand.ID, on screen: WindowPlacementEngine.Screen = mainScreen,
        window: CGRect = CGRect(x: 100, y: 100, width: 600, height: 400), gap: CGFloat = 0,
        step: Int = 0, cycle: WindowCycle = .off, restore: CGRect? = nil,
        lastTile: WindowCommand.ID? = nil,
        allScreens: [WindowPlacementEngine.Screen]? = nil
    ) -> WindowPlacementEngine.Placement? {
        WindowPlacementEngine.placement(
            for: WindowPlacementEngine.Input(
                command: command, windowFrame: window, screens: allScreens ?? [screen], gap: gap,
                step: step, cycle: cycle, restoreFrame: restore, lastTileCommand: lastTile))
    }

    /// 与 `placement` 相同，但只取排布结果中的 `frame`，测试里最常用的入口。
    static func frame(
        _ command: WindowCommand.ID, on screen: WindowPlacementEngine.Screen = mainScreen,
        window: CGRect = CGRect(x: 100, y: 100, width: 600, height: 400), gap: CGFloat = 0,
        step: Int = 0, cycle: WindowCycle = .off, restore: CGRect? = nil,
        lastTile: WindowCommand.ID? = nil,
        allScreens: [WindowPlacementEngine.Screen]? = nil
    ) -> CGRect? {
        placement(
            command, on: screen, window: window, gap: gap, step: step, cycle: cycle,
            restore: restore, lastTile: lastTile, allScreens: allScreens)?.frame
    }

    /// 像 `WindowMover` 那样连按 `command`：每次按下都从上一次落点出发，用于验证真实按键序列。
    static func presses(
        _ command: WindowCommand.ID, _ count: Int, from window: CGRect,
        on list: [WindowPlacementEngine.Screen]
    ) -> [WindowPlacementEngine.Placement] {
        let clock = Date(timeIntervalSince1970: 1_000_000)
        var memory = WindowActionMemory<Int>()
        var current = window
        var landed: [WindowPlacementEngine.Placement] = []
        for _ in 0..<count {
            let host = WindowPlacementEngine.screen(containing: current, in: list)!
            let decision = memory.decide(
                key: 1, command: command, currentFrame: current, currentScreenID: host.id,
                cycleLength: length(command, .displays, list), now: clock)
            let placement = WindowPlacementEngine.placement(
                for: WindowPlacementEngine.Input(
                    command: command, windowFrame: current, screens: list, step: decision.step,
                    cycle: .displays, originScreenID: decision.originScreenID))!
            memory.commit(
                key: 1, command: command, decision: decision, appliedFrame: placement.frame,
                screenID: placement.screenID, now: clock)
            current = placement.frame
            landed.append(placement)
        }
        return landed
    }

    /// 读取某命令在给定循环模式下的循环长度（可遍历的槽位数）。
    static func length(
        _ command: WindowCommand.ID, _ cycle: WindowCycle,
        _ list: [WindowPlacementEngine.Screen] = [mainScreen]
    ) -> Int {
        WindowPlacementEngine.cycleLength(for: command, screens: list, cycle: cycle)
    }

    /// 测试主入口：按固定顺序调用各测试函数，汇总结果并在失败时以退出码 1 结束。
    static func main() {
        testCatalog()
        testConventionLock()
        testTiling()
        testNonDivisible()
        testOffOriginScreens()
        testGaps()
        testSizing()
        testLargerSmaller()
        testNudges()
        testDisplays()
        testDisplayCycle()
        testRestore()
        testMemory()
        testFuzz()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Catalog

    /// 校验命令目录：35 条命令的完整性、ID/entryID 双向映射、分组归属与迭代标志的一致性。
    static func testCatalog() {
        let commands = WindowCommandCatalog.all
        expect(commands.count == 35, "catalog contains all 35 agreed commands")
        expect(commands.map(\.id) == WindowCommand.ID.allCases, "catalog covers every ID once")
        expect(
            Set(commands.map { $0.name.lowercased() }).count == commands.count, "names are unique")
        expect(commands.allSatisfy { !$0.name.isEmpty }, "names are non-empty")
        expect(commands.allSatisfy { !$0.sfSymbol.isEmpty }, "symbols are non-empty")

        for command in commands {
            expect(
                WindowCommandCatalog.command(forEntryID: command.entryID) == command,
                "\(command.id.rawValue) round-trips through its entry ID")
            expect(
                WindowCommandCatalog.command(id: command.id) == command,
                "\(command.id.rawValue) round-trips through its ID")
            expect(
                command.entryID.hasPrefix("window-command:"),
                "\(command.id.rawValue) is namespaced")
        }
        expect(
            WindowCommandCatalog.command(forEntryID: "window-command:unknown") == nil,
            "unknown entry IDs are rejected")
        expect(
            WindowCommandCatalog.command(forEntryID: "system-action:sleep") == nil,
            "system-action entry IDs are not claimed")

        let cycling = Set(commands.filter(\.cyclesOnRepeat).map(\.id))
        expect(
            cycling == [.leftHalf, .rightHalf, .topHalf, .bottomHalf],
            "only the four halves cycle on repeat")
        let moveOnly = Set(commands.filter { !$0.resizes }.map(\.id))
        expect(
            moveOnly == [.moveLeft, .moveRight, .moveUp, .moveDown],
            "only the four nudges leave the size alone")
        expect(
            Set(commands.filter { $0.kind == .fullscreen }.map(\.id)) == [.toggleFullscreen],
            "only Toggle Fullscreen is a fullscreen command")
        expect(
            Set(commands.filter { $0.kind == .restore }.map(\.id)) == [.restore],
            "only Restore is a restore command")
        expect(
            Set(commands.filter { $0.kind == .space }.map(\.id)) == [.previousSpace, .nextSpace],
            "only the two Space switches are space commands")
        expect(
            commands.filter { $0.kind == .space }.allSatisfy {
                WindowPlacementEngine.placement(
                    for: WindowPlacementEngine.Input(
                        command: $0.id, windowFrame: mainScreen.frame, screens: [mainScreen],
                        gap: 0, step: 0, restoreFrame: nil, lastTileCommand: nil)) == nil
            },
            "a space command resolves no placement, so the mover writes nothing")

        // 分组决定设置列表的展示；每个命令必须且只能落入一个分组。
        let grouped = WindowCommandCatalog.grouped()
        expect(
            grouped.flatMap(\.commands).count == commands.count, "grouping loses no command")
        expect(
            grouped.map(\.group) == WindowCommand.Group.allCases,
            "every group is represented, in declaration order")
        expect(grouped.first { $0.group == .halves }?.commands.count == 4, "four halves")
        expect(grouped.first { $0.group == .quarters }?.commands.count == 4, "four quarters")
        expect(grouped.first { $0.group == .fourths }?.commands.count == 2, "two fourths")
        expect(grouped.first { $0.group == .thirds }?.commands.count == 5, "five thirds")
        expect(grouped.first { $0.group == .sizing }?.commands.count == 11, "eleven sizing commands")
        expect(grouped.first { $0.group == .moving }?.commands.count == 6, "six moving commands")
        expect(grouped.first { $0.group == .spaces }?.commands.count == 2, "two space commands")

        expect(
            WindowPlacementEngine.isTileCommand(.leftHalf)
                && WindowPlacementEngine.isTileCommand(.centerHalf),
            "halves and center half are tiles")
        expect(
            !WindowPlacementEngine.isTileCommand(.maximize)
                && !WindowPlacementEngine.isTileCommand(.moveLeft),
            "free-floating commands are not tiles")

        // 全屏没有几何排布：mover 在请求 placement 之前就已分支处理。
        expect(frame(.toggleFullscreen) == nil, "Toggle Fullscreen produces no placement")
    }

    // MARK: - Convention lock

    /// 锁定 AX 坐标约定：+Y 向下，因此「上」贴 visibleFrame 的 minY。
    static func testConventionLock() {
        // AX 坐标系中 +Y 向下，因此上半区从 visibleFrame 的 minY 开始。
        expect(
            frame(.topHalf)?.minY == mainScreen.visibleFrame.minY,
            "top half is anchored at visibleFrame.minY (AX space, +Y down)")
        expect(
            frame(.bottomHalf)?.maxY == mainScreen.visibleFrame.maxY,
            "bottom half is anchored at visibleFrame.maxY")
        expect(
            frame(.topLeftQuarter)?.minY == mainScreen.visibleFrame.minY,
            "top left quarter sits at the top")
    }

    // MARK: - Tiling

    /// 校验半屏/四分之一/四分之三/三等分等平铺命令在参考屏幕上的精确 frame 与尺寸循环。
    static func testTiling() {
        expectRect(frame(.leftHalf)!, CGRect(x: 0, y: 0, width: 720, height: 900), "left half")
        expectRect(frame(.rightHalf)!, CGRect(x: 720, y: 0, width: 720, height: 900), "right half")
        expectRect(frame(.topHalf)!, CGRect(x: 0, y: 0, width: 1440, height: 450), "top half")
        expectRect(
            frame(.bottomHalf)!, CGRect(x: 0, y: 450, width: 1440, height: 450), "bottom half")

        expectRect(
            frame(.topLeftQuarter)!, CGRect(x: 0, y: 0, width: 720, height: 450), "top left quarter")
        expectRect(
            frame(.topRightQuarter)!, CGRect(x: 720, y: 0, width: 720, height: 450),
            "top right quarter")
        expectRect(
            frame(.bottomLeftQuarter)!, CGRect(x: 0, y: 450, width: 720, height: 450),
            "bottom left quarter")
        expectRect(
            frame(.bottomRightQuarter)!, CGRect(x: 720, y: 450, width: 720, height: 450),
            "bottom right quarter")

        let quarters = [
            frame(.topLeftQuarter)!, frame(.topRightQuarter)!, frame(.bottomLeftQuarter)!,
            frame(.bottomRightQuarter)!
        ]
        expect(
            quarters.reduce(CGRect.null) { $0.union($1) } == mainScreen.visibleFrame,
            "the four quarters union to the visible frame")
        var overlapping = false
        for i in quarters.indices {
            for j in quarters.indices where j > i {
                if !quarters[i].intersection(quarters[j]).isEmpty { overlapping = true }
            }
        }
        expect(!overlapping, "quarters never overlap")

        expectRect(
            frame(.firstThreeFourths)!, CGRect(x: 0, y: 0, width: 1080, height: 900),
            "first three fourths")
        expectRect(
            frame(.lastThreeFourths)!, CGRect(x: 360, y: 0, width: 1080, height: 900),
            "last three fourths")
        expect(
            frame(.firstThreeFourths)!.union(frame(.lastThreeFourths)!) == mainScreen.visibleFrame,
            "the two three-fourths cover the screen between them")
        expect(
            frame(.firstThreeFourths)!.intersection(frame(.lastThreeFourths)!) == frame(.centerHalf)!,
            "they overlap on exactly the centre half, so all three share the quarter grid")

        expectRect(frame(.firstThird)!, CGRect(x: 0, y: 0, width: 480, height: 900), "first third")
        expectRect(
            frame(.centerThird)!, CGRect(x: 480, y: 0, width: 480, height: 900), "center third")
        expectRect(frame(.lastThird)!, CGRect(x: 960, y: 0, width: 480, height: 900), "last third")
        expectRect(
            frame(.firstTwoThirds)!, CGRect(x: 0, y: 0, width: 960, height: 900), "first two thirds")
        expectRect(
            frame(.lastTwoThirds)!, CGRect(x: 480, y: 0, width: 960, height: 900), "last two thirds")

        expect(
            frame(.firstThird)!.union(frame(.lastTwoThirds)!) == mainScreen.visibleFrame,
            "first third and last two thirds partition the screen")
        expect(
            frame(.firstTwoThirds)!.union(frame(.lastThird)!) == mainScreen.visibleFrame,
            "first two thirds and last third partition the screen")

        // 尺寸循环只适用于半屏命令：½ → ⅓ → ⅔，并循环回绕。
        expectRect(
            frame(.leftHalf, step: 1, cycle: .sizes)!, frame(.firstThird)!,
            "left half step 1 is a third")
        expectRect(
            frame(.leftHalf, step: 2, cycle: .sizes)!, frame(.firstTwoThirds)!,
            "left half step 2 is two thirds")
        expectRect(
            frame(.leftHalf, step: 3, cycle: .sizes)!, frame(.leftHalf)!,
            "left half step 3 wraps to the half")
        expectRect(
            frame(.rightHalf, step: 1, cycle: .sizes)!, frame(.lastThird)!,
            "right half step 1 is a third")
        expectRect(
            frame(.rightHalf, step: 2, cycle: .sizes)!, frame(.lastTwoThirds)!,
            "right half step 2 is two thirds")
        expectRect(
            frame(.topHalf, step: 1, cycle: .sizes)!, CGRect(x: 0, y: 0, width: 1440, height: 300),
            "top half step 1 is a vertical third")
        expectRect(
            frame(.topHalf, step: 2, cycle: .sizes)!, CGRect(x: 0, y: 0, width: 1440, height: 600),
            "top half step 2 is vertical two thirds")
        expectRect(
            frame(.bottomHalf, step: 1, cycle: .sizes)!,
            CGRect(x: 0, y: 600, width: 1440, height: 300),
            "bottom half step 1 is a vertical third")
        expectRect(
            frame(.bottomHalf, step: 2, cycle: .sizes)!,
            CGRect(x: 0, y: 300, width: 1440, height: 600),
            "bottom half step 2 is vertical two thirds")

        // 传给不参与循环的命令的 step 必须被完全忽略。
        for step in 0...5 {
            expectRect(
                frame(.firstThird, step: step, cycle: .sizes)!, frame(.firstThird)!,
                "non-cycling commands ignore step \(step)")
            expectRect(
                frame(.maximize, step: step, cycle: .sizes)!, frame(.maximize)!,
                "maximize ignores step \(step)")
            expectRect(
                frame(.leftHalf, step: step)!, frame(.leftHalf)!,
                "cycling switched off ignores step \(step)")
        }
        // 负数 step 既不能崩溃，也不能越出循环范围。
        expectRect(
            frame(.leftHalf, step: -1, cycle: .sizes)!, frame(.firstTwoThirds)!,
            "negative steps normalize")
    }

    // MARK: - Non-divisible widths

    /// 在不可整除的宽度（如 1366）上验证相邻分块共边、覆盖完整且宽度差不超过 1 点。
    static func testNonDivisible() {
        // 1366 是四分之一分法的平局情形：它的四分之一恰好落在 .5 上。
        for width in [1441, 1000, 1367, 1366] as [CGFloat] {
            let screen = WindowPlacementEngine.Screen(
                id: 9, frame: CGRect(x: 0, y: 0, width: width, height: 901),
                visibleFrame: CGRect(x: 0, y: 0, width: width, height: 901))
            let first = frame(.firstThird, on: screen)!
            let center = frame(.centerThird, on: screen)!
            let last = frame(.lastThird, on: screen)!
            expect(first.maxX == center.minX, "\(width): first/center thirds share an edge exactly")
            expect(center.maxX == last.minX, "\(width): center/last thirds share an edge exactly")
            expect(
                first.union(center).union(last) == screen.visibleFrame,
                "\(width): thirds still cover the whole screen")

            let left = frame(.leftHalf, on: screen)!
            let right = frame(.rightHalf, on: screen)!
            expect(left.maxX == right.minX, "\(width): halves share an edge exactly")
            expect(left.union(right) == screen.visibleFrame, "\(width): halves cover the screen")
            expect(abs(left.width - right.width) <= 1, "\(width): halves differ by at most a point")

            let top = frame(.topHalf, on: screen)!
            let bottom = frame(.bottomHalf, on: screen)!
            expect(top.maxY == bottom.minY, "\(width): vertical halves share an edge exactly")

            let firstFourths = frame(.firstThreeFourths, on: screen)!
            let lastFourths = frame(.lastThreeFourths, on: screen)!
            expect(
                abs(firstFourths.width - lastFourths.width) <= 1,
                "\(width): the two three-fourths differ by at most a point")
            expect(
                abs(firstFourths.width - width * 0.75) <= 1,
                "\(width): three fourths is three quarters of the screen")
            expect(
                firstFourths.union(lastFourths) == screen.visibleFrame,
                "\(width): the two three-fourths still cover the screen")
        }
    }

    // MARK: - Off-origin displays

    /// 验证非零原点的显示器（含负坐标）与带菜单栏/Dock 预留的 visibleFrame 上的排布。
    static func testOffOriginScreens() {
        // 位于主显示器右上方、但 AX 坐标系中 Y 为负的显示器。
        let high = WindowPlacementEngine.Screen(
            id: 2, frame: CGRect(x: 1920, y: -300, width: 2560, height: 1440),
            visibleFrame: CGRect(x: 1920, y: -300, width: 2560, height: 1440))
        expectRect(
            frame(.leftHalf, on: high, window: CGRect(x: 2000, y: 0, width: 400, height: 300))!,
            CGRect(x: 1920, y: -300, width: 1280, height: 1440), "left half on an off-origin display")
        expect(
            frame(.topHalf, on: high, window: CGRect(x: 2000, y: 0, width: 400, height: 300))!.minY
                == -300, "top half honours a negative minY")

        // 位于主显示器左侧且偏下方的显示器。
        let low = WindowPlacementEngine.Screen(
            id: 3, frame: CGRect(x: -1440, y: 200, width: 1440, height: 900),
            visibleFrame: CGRect(x: -1440, y: 200, width: 1440, height: 900))
        expectRect(
            frame(.rightHalf, on: low, window: CGRect(x: -1000, y: 300, width: 400, height: 300))!,
            CGRect(x: -720, y: 200, width: 720, height: 900), "right half on a negative-X display")
        expectRect(
            frame(.maximize, on: low, window: CGRect(x: -1000, y: 300, width: 400, height: 300))!,
            low.visibleFrame, "maximize on a negative-X display")

        // visibleFrame 小于完整 frame（为菜单栏与 Dock 预留了空间）。
        let reserved = WindowPlacementEngine.Screen(
            id: 4, frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 25, width: 1440, height: 800))
        expectRect(
            frame(.topHalf, on: reserved)!, CGRect(x: 0, y: 25, width: 1440, height: 400),
            "tiles respect a reserved visible frame")
        expectRect(
            frame(.maximize, on: reserved)!, reserved.visibleFrame, "maximize never covers the menu bar")
    }

    // MARK: - Gaps

    /// 验证 gap 的内缩与外/内边缘差异，以及负数、NaN、无穷、超大 gap 的退化处理。
    static func testGaps() {
        expectRect(
            frame(.leftHalf, gap: 10)!, CGRect(x: 10, y: 10, width: 705, height: 880),
            "left half with a 10pt gap")
        expectRect(
            frame(.rightHalf, gap: 10)!, CGRect(x: 725, y: 10, width: 705, height: 880),
            "right half with a 10pt gap")
        expect(
            frame(.leftHalf, gap: 10)!.maxX + 10 == frame(.rightHalf, gap: 10)!.minX,
            "the gutter between halves is exactly the gap")
        expect(
            frame(.topHalf, gap: 10)!.maxY + 10 == frame(.bottomHalf, gap: 10)!.minY,
            "the gutter between vertical halves is exactly the gap")

        // 每条外边缘内缩一个完整 gap，每道内部间隔恰好等于一个 gap。
        let quarters = [
            frame(.topLeftQuarter, gap: 10)!, frame(.topRightQuarter, gap: 10)!,
            frame(.bottomLeftQuarter, gap: 10)!, frame(.bottomRightQuarter, gap: 10)!
        ]
        expect(quarters[0].maxX + 10 == quarters[1].minX, "quarters: vertical gutter is the gap")
        expect(quarters[0].maxY + 10 == quarters[2].minY, "quarters: horizontal gutter is the gap")
        expect(
            quarters.allSatisfy {
                $0.minX >= 10 && $0.minY >= 10 && $0.maxX <= 1430 && $0.maxY <= 890
            }, "quarters stay inset from every screen edge")

        // 四分之三分法：外侧边缘取完整 gap，内侧边缘取一半。
        expectRect(
            frame(.firstThreeFourths, gap: 10)!, CGRect(x: 10, y: 10, width: 1065, height: 880),
            "first three fourths with a 10pt gap")
        expectRect(
            frame(.lastThreeFourths, gap: 10)!, CGRect(x: 365, y: 10, width: 1065, height: 880),
            "last three fourths with a 10pt gap")

        // 三等分：两道间隔，都精确等于 gap。
        expect(
            frame(.firstThird, gap: 10)!.maxX + 10 == frame(.centerThird, gap: 10)!.minX,
            "thirds: first/center gutter is the gap")
        expect(
            frame(.centerThird, gap: 10)!.maxX + 10 == frame(.lastThird, gap: 10)!.minX,
            "thirds: center/last gutter is the gap")

        // 奇数 gap 折半并取整后不得产生偏移。
        expect(
            frame(.leftHalf, gap: 9)!.maxX + 9 == frame(.rightHalf, gap: 9)!.minX,
            "an odd gap still produces an exact gutter")

        expectRect(
            frame(.maximize, gap: 12)!, CGRect(x: 12, y: 12, width: 1416, height: 876),
            "maximize honours the gap")

        // 退化 gap 绝不能产生不可用的窗口。
        for gap in [-5, 0, 10_000] as [CGFloat] {
            let rect = frame(.leftHalf, gap: gap)!
            expect(rect.width > 0 && rect.height > 0, "gap \(gap) still yields a positive tile")
            expect(
                mainScreen.visibleFrame.contains(rect), "gap \(gap) keeps the tile on screen")
        }
        expectRect(frame(.leftHalf, gap: -5)!, frame(.leftHalf)!, "a negative gap reads as zero")
        // 所有非有限值都按 0 处理，因此 NaN 与无穷行为一致。
        expectRect(frame(.leftHalf, gap: .nan)!, frame(.leftHalf)!, "a NaN gap reads as zero")
        expectRect(
            frame(.leftHalf, gap: .infinity)!, frame(.leftHalf)!, "an infinite gap reads as zero")
        // 仅仅过大（但有限）的 gap 会被截断到上限，而不是归零。
        expectRect(
            frame(.leftHalf, gap: 10_000)!, frame(.leftHalf, gap: 90)!,
            "an oversized finite gap is capped to a tenth of the smaller dimension")
    }

    // MARK: - Sizing

    /// 验证最大化、适应屏幕、居中等尺寸类命令的结果、幂等性与超尺寸窗口的收缩。
    static func testSizing() {
        expectRect(frame(.maximize)!, mainScreen.visibleFrame, "maximize fills the visible frame")

        let almost = frame(.almostMaximize)!
        expectRect(almost, CGRect(x: 72, y: 45, width: 1296, height: 810), "almost maximize")
        expectRect(
            frame(.almostMaximize, window: almost)!, almost, "almost maximize is idempotent")
        expect(
            almost.midX == mainScreen.visibleFrame.midX
                && almost.midY == mainScreen.visibleFrame.midY,
            "almost maximize stays centred")

        let reasonable = frame(.reasonableSize)!
        expectRect(
            reasonable, CGRect(x: 288, y: 180, width: 864, height: 540), "reasonable size is 60%")
        expectRect(
            frame(.reasonableSize, window: reasonable)!, reasonable, "reasonable size is idempotent")

        // 小显示器达不到上限，因此展示出来的就是比例值本身。
        let small = WindowPlacementEngine.Screen(
            id: 7, frame: CGRect(x: 0, y: 0, width: 1280, height: 800),
            visibleFrame: CGRect(x: 0, y: 0, width: 1280, height: 800))
        expectRect(
            frame(.reasonableSize, on: small)!, CGRect(x: 256, y: 160, width: 768, height: 480),
            "reasonable size is uncapped on a small display")

        // 大显示器会触达上限，这正是该命令与显示器无关的原因。
        let large = WindowPlacementEngine.Screen(
            id: 8, frame: CGRect(x: 0, y: 0, width: 3840, height: 2160),
            visibleFrame: CGRect(x: 0, y: 0, width: 3840, height: 2160))
        let capped = frame(.reasonableSize, on: large)!
        expect(
            capped.width == 1025 && capped.height == 900, "reasonable size caps at 1025×900")
        expect(large.visibleFrame.contains(capped), "a capped reasonable size stays on screen")
        expect(
            abs(capped.midX - large.visibleFrame.midX) <= 0.5
                && abs(capped.midY - large.visibleFrame.midY) <= 0.5,
            "a capped reasonable size stays centred")

        let window = CGRect(x: 100, y: 200, width: 300, height: 400)
        let tall = frame(.maximizeHeight, window: window)!
        expect(
            tall.minX == 100 && tall.width == 300, "maximize height preserves minX and width exactly")
        expect(tall.minY == 0 && tall.height == 900, "maximize height fills the canvas vertically")

        let wide = frame(.maximizeWidth, window: window)!
        expect(
            wide.minY == 200 && wide.height == 400, "maximize width preserves minY and height exactly")
        expect(wide.minX == 0 && wide.width == 1440, "maximize width fills the canvas horizontally")

        // 屏幕外的窗口不能变成满高后仍留在屏幕外。
        let stray = CGRect(x: -900, y: -900, width: 200, height: 150)
        let strayTall = frame(.maximizeHeight, window: stray)!
        expect(strayTall.minX == 0 && strayTall.width == 200, "maximize height clamps a stray x")
        expect(
            !strayTall.intersection(mainScreen.visibleFrame).isNull,
            "maximize height brings a stray window back on screen")
        let strayWide = frame(.maximizeWidth, window: stray)!
        expect(strayWide.minY == 0 && strayWide.height == 150, "maximize width clamps a stray y")
        expect(
            !strayWide.intersection(mainScreen.visibleFrame).isNull,
            "maximize width brings a stray window back on screen")

        expectRect(
            frame(.center, window: window)!, CGRect(x: 570, y: 250, width: 300, height: 400),
            "center preserves the size and centres it")
        expectRect(
            frame(.center, window: frame(.center, window: window)!)!,
            frame(.center, window: window)!, "center is idempotent")

        // 比屏幕还大的窗口必须被收缩，而不是居中到屏幕之外。
        let huge = CGRect(x: -500, y: -500, width: 3000, height: 2000)
        let centred = frame(.center, window: huge)!
        expect(
            centred.width <= 1440 && centred.height <= 900, "center clamps an oversized window")
        expect(mainScreen.visibleFrame.contains(centred), "a clamped center stays on screen")

        expectRect(
            frame(.centerHalf)!, CGRect(x: 360, y: 0, width: 720, height: 900),
            "center half is half the screen's area")
        expectRect(
            frame(.centerTwoThirds)!, CGRect(x: 240, y: 0, width: 960, height: 900),
            "center two thirds is two thirds of the width, centred")
    }

    // MARK: - Make Larger / Make Smaller

    /// 验证放大/缩小命令的对称性（放大后再缩小可精确回到原矩形）与饱和行为。
    static func testLargerSmaller() {
        let start = CGRect(x: 100, y: 100, width: 600, height: 400)
        let larger = frame(.makeLarger, window: start)!
        expect(larger.width > start.width && larger.height > start.height, "make larger grows")
        // 这条断言印证了采用「相对于屏幕的步长」的必要性：相对于尺寸本身的步长无法精确往返。
        expectRect(
            frame(.makeSmaller, window: larger)!, start,
            "larger then smaller returns the exact original rect")
        let smaller = frame(.makeSmaller, window: start)!
        expectRect(
            frame(.makeLarger, window: smaller)!, start,
            "smaller then larger returns the exact original rect")
        expect(larger.midX == start.midX && larger.midY == start.midY, "growing keeps the centre")
        expect(smaller.midX == start.midX && smaller.midY == start.midY, "shrinking keeps the centre")

        // 反复缩小会在下限处饱和，而不是塌缩到零。
        var shrinking = start
        for _ in 0..<40 { shrinking = frame(.makeSmaller, window: shrinking)! }
        expect(shrinking.width > 0 && shrinking.height > 0, "40 shrinks never collapse the window")
        expectRect(
            frame(.makeSmaller, window: shrinking)!, shrinking, "shrinking saturates into a no-op")

        // 反复放大最终收敛到画布尺寸。
        var growing = start
        for _ in 0..<40 { growing = frame(.makeLarger, window: growing)! }
        expectRect(growing, mainScreen.visibleFrame, "40 grows converge on the maximized frame")
        expectRect(frame(.makeLarger, window: growing)!, growing, "growing saturates into a no-op")

        // 带 gap 时，放大收敛到带 gap 的画布，而不是原始 visibleFrame。
        var gapped = start
        for _ in 0..<40 { gapped = frame(.makeLarger, window: gapped, gap: 12)! }
        expectRect(gapped, frame(.maximize, gap: 12)!, "growing respects the gap")
    }

    // MARK: - Nudges

    /// 验证四个微调命令只改变位置、不改变尺寸，并在抵达边界时停住。
    static func testNudges() {
        let start = CGRect(x: 300, y: 300, width: 600, height: 400)
        for command in [WindowCommand.ID.moveLeft, .moveRight, .moveUp, .moveDown] {
            let moved = frame(command, window: start)!
            expect(moved.size == start.size, "\(command.rawValue) leaves the size untouched")
        }
        expectRect(
            frame(.moveLeft, window: start)!, CGRect(x: 228, y: 300, width: 600, height: 400),
            "move left nudges by 5% of the screen width")
        expectRect(
            frame(.moveUp, window: start)!, CGRect(x: 300, y: 255, width: 600, height: 400),
            "move up nudges by 5% of the screen height")
        expectRect(
            frame(.moveRight, window: frame(.moveLeft, window: start)!)!, start,
            "left then right returns the original position")
        expectRect(
            frame(.moveDown, window: frame(.moveUp, window: start)!)!, start,
            "up then down returns the original position")

        var sliding = start
        for _ in 0..<30 { sliding = frame(.moveLeft, window: sliding)! }
        expect(sliding.minX == 0, "30 nudges left end flush against the canvas edge")
        expect(sliding.size == start.size, "nudging to the edge never resizes")
        expectRect(frame(.moveLeft, window: sliding)!, sliding, "a flush window nudges no further")

        // 比画布更宽的窗口会钉住其前缘，而不是滑出画布。
        let overWide = CGRect(x: 100, y: 100, width: 2000, height: 400)
        let pinned = frame(.moveLeft, window: overWide)!
        expect(pinned.minX == 0, "an oversized window pins to the canvas edge")
        expect(pinned.size == overWide.size, "an oversized nudge never resizes")
    }

    // MARK: - Displays

    /// 验证多显示器场景：左到右排序、跨屏移动、按比例映射与重叠归属判定。
    static func testDisplays() {
        expect(frame(.nextDisplay) == nil, "a single display makes Next Display a no-op")
        expect(frame(.previousDisplay) == nil, "a single display makes Previous Display a no-op")

        let left = mainScreen
        let right = WindowPlacementEngine.Screen(
            id: 2, frame: CGRect(x: 1440, y: 0, width: 2560, height: 1440),
            visibleFrame: CGRect(x: 1440, y: 0, width: 2560, height: 1440))
        // 故意打乱顺序，用以证明排序是推导出来的，而非沿用传入顺序。
        let both = screens(right, left)
        expect(WindowPlacementEngine.ordered(both).map(\.id) == [1, 2], "displays order left-to-right")

        let leftHalfOnLeft = frame(.leftHalf, on: left)!
        let onRight = frame(
            .nextDisplay, window: leftHalfOnLeft, allScreens: both)!
        expectRect(
            onRight, CGRect(x: 1440, y: 0, width: 1280, height: 1440),
            "a left half maps proportionally onto the larger display")
        expect(right.visibleFrame.contains(onRight), "the moved window stays inside the destination")

        expectRect(
            frame(.previousDisplay, window: onRight, allScreens: both)!, leftHalfOnLeft,
            "next then previous round-trips to the original frame")

        // 两个方向都会回绕。
        expect(
            WindowPlacementEngine.placement(
                for: WindowPlacementEngine.Input(
                    command: .previousDisplay, windowFrame: leftHalfOnLeft, screens: both)
            )?.screenID == 2, "previous from the first display wraps to the last")
        expect(
            WindowPlacementEngine.placement(
                for: WindowPlacementEngine.Input(command: .nextDisplay, windowFrame: onRight, screens: both)
            )?.screenID == 1, "next from the last display wraps to the first")

        // 记忆的平铺方式会在目标显示器上精确重算，包含 gap。
        expectRect(
            frame(.nextDisplay, window: leftHalfOnLeft, gap: 10, lastTile: .leftHalf, allScreens: both)!,
            frame(.leftHalf, on: right, gap: 10)!,
            "a remembered tile is re-derived exactly on the destination")
        expectRect(
            frame(
                .nextDisplay, window: frame(.firstThird, on: left)!, lastTile: .firstThird,
                allScreens: both)!,
            frame(.firstThird, on: right)!,
            "a remembered third is re-derived exactly on the destination")

        // 通过重叠面积判定窗口归属哪块显示器。
        expect(
            WindowPlacementEngine.screen(
                containing: CGRect(x: 1150, y: 0, width: 500, height: 100), in: both)?.id == 1,
            "a straddling window belongs to the display showing more of it")
        expect(
            WindowPlacementEngine.screen(
                containing: CGRect(x: 1300, y: 0, width: 500, height: 100), in: both)?.id == 2,
            "the overlap majority flips with the window")
        expect(
            WindowPlacementEngine.screen(
                containing: CGRect(x: -5000, y: -5000, width: 100, height: 100), in: both) != nil,
            "a window off every display still resolves to one")
    }

    // MARK: - Cycling across displays

    /// 验证跨显示器的重复按键循环：条带顺序、镜像、回绕与目标屏 gap 的采用。
    static func testDisplayCycle() {
        let left = mainScreen
        let right = WindowPlacementEngine.Screen(
            id: 2, frame: CGRect(x: 1440, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 1440, y: 0, width: 1440, height: 900))
        let both = screens(right, left)
        let onLeft = CGRect(x: 100, y: 100, width: 600, height: 400)

        // 每条显示器贡献两个半屏槽位，因此长度就是简单的乘积。
        expect(length(.leftHalf, .off, both) == 1, "cycling off is a length of one")
        expect(length(.leftHalf, .sizes, both) == 3, "the size cycle is three steps")
        expect(length(.leftHalf, .displays, both) == 4, "two displays give four slots")
        expect(length(.maximize, .displays, both) == 1, "a non-cycling command never cycles")
        expect(
            length(.leftHalf, .displays) == 1,
            "one display makes the display leg a no-op")

        // issue 要求的顺序：Left 反向遍历整条条带，并循环回绕。
        let expected: [CGRect] = [
            frame(.leftHalf, on: left)!, frame(.rightHalf, on: right)!,
            frame(.leftHalf, on: right)!, frame(.rightHalf, on: left)!
        ]
        for (step, want) in expected.enumerated() {
            expectRect(
                frame(.leftHalf, window: onLeft, step: step, cycle: .displays, allScreens: both)!,
                want, "left half display step \(step)")
        }
        expectRect(
            frame(.leftHalf, window: onLeft, step: 4, cycle: .displays, allScreens: both)!,
            expected[0], "the display cycle wraps")
        expectRect(
            frame(.leftHalf, window: onLeft, step: -1, cycle: .displays, allScreens: both)!,
            expected[3], "a negative display step normalises")

        // Right 是它的精确镜像，因此两个快捷键以相反方向扫过条带。
        for (step, want) in [
            frame(.rightHalf, on: left)!, frame(.leftHalf, on: right)!,
            frame(.rightHalf, on: right)!, frame(.leftHalf, on: left)!
        ].enumerated() {
            expectRect(
                frame(.rightHalf, window: onLeft, step: step, cycle: .displays, allScreens: both)!,
                want, "right half display step \(step)")
        }

        // Top 与 Bottom 遍历同一条条带，但各自保持自己的轴向。
        expectRect(
            frame(.topHalf, window: onLeft, step: 1, cycle: .displays, allScreens: both)!,
            frame(.bottomHalf, on: right)!, "top half step 1 is the bottom half of the next display")
        expectRect(
            frame(.bottomHalf, window: onLeft, step: 1, cycle: .displays, allScreens: both)!,
            frame(.topHalf, on: right)!, "bottom half step 1 is the top half of the next display")

        // 无论还接入了哪些显示器，尺寸循环都停留在宿主显示器上。
        for step in 0..<3 {
            expectRect(
                frame(.leftHalf, window: onLeft, step: step, cycle: .sizes, allScreens: both)!,
                frame(.leftHalf, on: left, step: step, cycle: .sizes)!,
                "the size cycle ignores the other display at step \(step)")
        }

        // 真实连按：从第二次起，窗口已位于上一次刚被移到的显示器上。
        let onRight = CGRect(x: 1540, y: 100, width: 600, height: 400)
        let walked = presses(.leftHalf, 5, from: onRight, on: both).map(\.frame)
        let walk: [CGRect] = [
            frame(.leftHalf, on: right)!, frame(.rightHalf, on: left)!,
            frame(.leftHalf, on: left)!, frame(.rightHalf, on: right)!,
            frame(.leftHalf, on: right)!
        ]
        for (press, want) in walk.enumerated() {
            expectRect(walked[press], want, "left half from the right display, press \(press + 1)")
        }

        // 起点显示器已拔掉时，回退到窗口当前所在的显示器。
        expectRect(
            WindowPlacementEngine.placement(
                for: WindowPlacementEngine.Input(
                    command: .leftHalf, windowFrame: onLeft, screens: both, step: 1,
                    cycle: .displays, originScreenID: 99))!.frame,
            expected[1], "an unplugged origin counts from the host")

        // 无论从哪块显示器起手，一整圈真实连按都会不重不漏地访问每个槽位。
        for start in [onLeft, onRight] {
            for command in [WindowCommand.ID.leftHalf, .rightHalf] {
                let lap = presses(command, length(command, .displays, both), from: start, on: both)
                expect(
                    Set(lap.map(\.frame)).count == lap.count,
                    "\(command.rawValue) visits four distinct slots")
                expect(
                    Set(lap.map(\.screenID)) == [1, 2],
                    "\(command.rawValue) reaches both displays")
            }
        }

        // gap 属于目标显示器，而不是窗口最初所在的那块。
        let narrow = WindowPlacementEngine.Screen(
            id: 3, frame: CGRect(x: 1440, y: 0, width: 200, height: 900),
            visibleFrame: CGRect(x: 1440, y: 0, width: 200, height: 900))
        expectRect(
            frame(
                .leftHalf, window: onLeft, gap: 100, step: 2, cycle: .displays,
                allScreens: screens(left, narrow))!,
            frame(.leftHalf, on: narrow, gap: 100)!,
            "the destination display sanitises the gap")

        // 任何模式下，非循环命令都不会得到可遍历的链条。
        for command in WindowCommand.ID.allCases
        where !WindowCommandCatalog.cyclesOnRepeat.contains(command) {
            for cycle in WindowCycle.allCases {
                expect(
                    length(command, cycle, both) == 1,
                    "\(command.rawValue) has no cycle to walk under \(cycle.rawValue)")
            }
        }
    }

    // MARK: - Restore

    /// 验证还原命令：无记录时空操作、可用记录原样返回、屏幕外还原点被拉回屏幕内。
    static func testRestore() {
        expect(frame(.restore) == nil, "restore with no recorded frame does nothing")

        let recorded = CGRect(x: 123, y: 234, width: 456, height: 321)
        expectRect(
            frame(.restore, restore: recorded)!, recorded, "a valid restore frame comes back untouched")

        // 落在所有显示器之外、无处安放的还原点会被恢复回屏幕内。
        let stranded = CGRect(x: 9000, y: 9000, width: 400, height: 300)
        let recovered = frame(.restore, restore: stranded)!
        expect(recovered.size == stranded.size, "a stranded restore keeps its size")
        expect(
            mainScreen.visibleFrame.contains(recovered), "a stranded restore lands back on screen")
        expect(
            recovered.midX == mainScreen.visibleFrame.midX,
            "a stranded restore is re-centred horizontally")
    }

    // MARK: - Action memory

    /// 验证动作记忆的循环推进、重置条件、还原点保留、超时、LRU 淘汰与容量边界。
    static func testMemory() {
        let clock = Date(timeIntervalSince1970: 1_000_000)
        let half = CGRect(x: 0, y: 0, width: 720, height: 900)
        let original = CGRect(x: 100, y: 100, width: 600, height: 400)

        // 首次出现的窗口：step 为 0，无可还原内容，当前 frame 即为锚点。
        var memory = WindowActionMemory<Int>()
        var decision = memory.decide(
            key: 1, command: .leftHalf, currentFrame: original, currentScreenID: 1,
            cycleLength: 3, now: clock)
        expect(decision.step == 0, "a first press starts at step 0")
        expect(!decision.canRestore, "a never-seen window has nothing to restore to")
        expectRect(decision.restoreFrame, original, "the first press captures the original frame")
        expect(decision.originScreenID == 1, "a first press starts its chain on its own display")
        memory.commit(
            key: 1, command: .leftHalf, decision: decision, appliedFrame: half, screenID: 1,
            now: clock)

        // 重复按下会推进循环，且从不动摇还原点。
        for expected in [1, 2, 0, 1] {
            let applied = frame(.leftHalf, step: expected)!
            decision = memory.decide(
                key: 1, command: .leftHalf, currentFrame: memory.record(for: 1)!.appliedFrame,
                currentScreenID: 1, cycleLength: 3, now: clock)
            expect(decision.step == expected, "the cycle advances to step \(expected)")
            expectRect(decision.restoreFrame, original, "the restore point survives step \(expected)")
            expect(decision.canRestore, "a seen window can be restored")
            memory.commit(
                key: 1, command: .leftHalf, decision: decision, appliedFrame: applied, screenID: 1,
                now: clock)
        }

        // 命令、显示器或窗口任一不同，都会重置循环。
        decision = memory.decide(
            key: 1, command: .rightHalf, currentFrame: memory.record(for: 1)!.appliedFrame,
            currentScreenID: 1, cycleLength: 3, now: clock)
        expect(decision.step == 0, "a different command restarts the cycle")
        expectRect(decision.restoreFrame, original, "a different command keeps the restore point")
        decision = memory.decide(
            key: 1, command: .leftHalf, currentFrame: memory.record(for: 1)!.appliedFrame,
            currentScreenID: 2, cycleLength: 3, now: clock)
        expect(decision.step == 0, "a different display restarts the cycle")
        expect(decision.originScreenID == 2, "a restarted chain starts on the current display")
        decision = memory.decide(
            key: 99, command: .leftHalf, currentFrame: original, currentScreenID: 1,
            cycleLength: 3, now: clock)
        expect(decision.step == 0 && !decision.canRestore, "another window has its own chain")

        // 被显示器循环带到别处的链条，仍从起始处继续计数。
        var crossing = WindowActionMemory<Int>()
        let crossingSeed = crossing.decide(
            key: 1, command: .leftHalf, currentFrame: original, currentScreenID: 1,
            cycleLength: 4, now: clock)
        crossing.commit(
            key: 1, command: .leftHalf, decision: crossingSeed, appliedFrame: half, screenID: 2,
            now: clock)
        decision = crossing.decide(
            key: 1, command: .leftHalf, currentFrame: half, currentScreenID: 2, cycleLength: 4,
            now: clock)
        expect(decision.step == 1, "a press on the display the chain landed on continues it")
        expect(decision.originScreenID == 1, "a continued chain keeps its origin display")

        // 用户手动拖动会重置循环并重新锚定还原点。
        var dragged = WindowActionMemory<Int>()
        let seed = dragged.decide(
            key: 1, command: .leftHalf, currentFrame: original, currentScreenID: 1,
            cycleLength: 3, now: clock)
        dragged.commit(
            key: 1, command: .leftHalf, decision: seed, appliedFrame: half, screenID: 1, now: clock)
        let movedByUser = CGRect(x: 400, y: 400, width: 500, height: 300)
        decision = dragged.decide(
            key: 1, command: .leftHalf, currentFrame: movedByUser, currentScreenID: 1,
            cycleLength: 3, now: clock)
        expect(decision.step == 0, "a user drag restarts the cycle")
        expectRect(decision.restoreFrame, movedByUser, "a user drag re-anchors the restore point")
        expect(decision.lastTileCommand == nil, "a user drag forgets the remembered tile")

        // 会取整而偏离目标 1 个点的应用，绝不能被误判为用户拖动。
        let quantised = CGRect(x: half.minX + 1, y: half.minY, width: half.width - 1, height: half.height)
        decision = dragged.decide(
            key: 1, command: .leftHalf, currentFrame: quantised, currentScreenID: 1,
            cycleLength: 3, now: clock)
        expect(decision.step == 1, "a sub-tolerance difference keeps the cycle running")
        expect(decision.lastTileCommand == .leftHalf, "an untouched tile is remembered")

        // 循环开关会把一切都固定在第 0 步。
        var pinned = WindowActionMemory<Int>()
        var pinnedDecision = pinned.decide(
            key: 1, command: .leftHalf, currentFrame: original, currentScreenID: 1,
            cycleLength: 1, now: clock)
        for _ in 0..<5 {
            pinned.commit(
                key: 1, command: .leftHalf, decision: pinnedDecision, appliedFrame: half,
                screenID: 1, now: clock)
            pinnedDecision = pinned.decide(
                key: 1, command: .leftHalf, currentFrame: half, currentScreenID: 1,
                cycleLength: 1, now: clock)
            expect(pinnedDecision.step == 0, "cycling off pins every repeat to step 0")
        }

        // 即使开启循环，非循环命令也永不推进。
        var nonCycling = WindowActionMemory<Int>()
        let maximized = mainScreen.visibleFrame
        var nonDecision = nonCycling.decide(
            key: 1, command: .maximize, currentFrame: original, currentScreenID: 1,
            cycleLength: length(.maximize, .sizes), now: clock)
        for _ in 0..<5 {
            nonCycling.commit(
                key: 1, command: .maximize, decision: nonDecision, appliedFrame: maximized,
                screenID: 1, now: clock)
            nonDecision = nonCycling.decide(
                key: 1, command: .maximize, currentFrame: maximized, currentScreenID: 1,
                cycleLength: length(.maximize, .sizes), now: clock)
            expect(nonDecision.step == 0, "a non-cycling command never advances")
        }

        var timed = WindowActionMemory<Int>(cycleTimeout: 60)
        let timedSeed = timed.decide(
            key: 1, command: .leftHalf, currentFrame: original, currentScreenID: 1,
            cycleLength: 3, now: clock)
        timed.commit(
            key: 1, command: .leftHalf, decision: timedSeed, appliedFrame: half, screenID: 1,
            now: clock)
        expect(
            timed.decide(
                key: 1, command: .leftHalf, currentFrame: half, currentScreenID: 1,
                cycleLength: 3, now: clock.addingTimeInterval(30)
            ).step == 1, "a cycle inside the timeout continues")
        expect(
            timed.decide(
                key: 1, command: .leftHalf, currentFrame: half, currentScreenID: 1,
                cycleLength: 3, now: clock.addingTimeInterval(120)
            ).step == 0, "a cycle past the timeout restarts")

        // 还原点能在一连串不同命令之后依然保留，且 Restore 是幂等的。
        var run = WindowActionMemory<Int>()
        var runDecision = run.decide(
            key: 1, command: .leftHalf, currentFrame: original, currentScreenID: 1,
            cycleLength: 3, now: clock)
        run.commit(
            key: 1, command: .leftHalf, decision: runDecision, appliedFrame: half, screenID: 1,
            now: clock)
        var applied = half
        for command in [WindowCommand.ID.maximize, .topRightQuarter, .centerThird] {
            runDecision = run.decide(
                key: 1, command: command, currentFrame: applied, currentScreenID: 1,
                cycleLength: 3, now: clock)
            applied = frame(command)!
            run.commit(
                key: 1, command: command, decision: runDecision, appliedFrame: applied, screenID: 1,
                now: clock)
        }
        runDecision = run.decide(
            key: 1, command: .restore, currentFrame: applied, currentScreenID: 1, cycleLength: 3,
            now: clock)
        expectRect(
            runDecision.restoreFrame, original, "the restore point survives three other commands")
        expect(runDecision.canRestore, "the window can be restored after a run of commands")
        let restored = frame(.restore, restore: runDecision.restoreFrame)!
        expectRect(restored, original, "restore returns the true original frame")
        run.commit(
            key: 1, command: .restore, decision: runDecision, appliedFrame: restored, screenID: 1,
            now: clock)
        let second = run.decide(
            key: 1, command: .restore, currentFrame: restored, currentScreenID: 1,
            cycleLength: 3, now: clock)
        expectRect(
            frame(.restore, restore: second.restoreFrame)!, original, "a second restore is idempotent")

        // 全屏会打断循环链条，但保留还原点。
        run.forgetCycle(key: 1)
        expect(run.record(for: 1)?.step == 0, "forgetCycle resets the step")
        expect(
            run.record(for: 1)?.originScreenID == run.record(for: 1)?.screenID,
            "forgetCycle restarts the chain on the window's current display")
        expectRect(
            run.record(for: 1)!.restoreFrame, original, "forgetCycle keeps the restore point")

        // 容量有界，保留最近使用的记录。
        var bounded = WindowActionMemory<Int>(capacity: 64)
        for key in 0..<100 {
            let boundedDecision = bounded.decide(
                key: key, command: .leftHalf, currentFrame: original, currentScreenID: 1,
                cycleLength: 3, now: clock)
            bounded.commit(
                key: key, command: .leftHalf, decision: boundedDecision, appliedFrame: half,
                screenID: 1, now: clock)
        }
        expect(bounded.count == 64, "the memory is bounded at its capacity")
        expect(bounded.record(for: 99) != nil, "the most recent key survives eviction")
        expect(bounded.record(for: 0) == nil, "the oldest key is evicted")
        expect(bounded.record(for: 36) != nil, "the 64 most recent keys survive")

        bounded.forget { $0 % 2 == 0 }
        expect(bounded.record(for: 99) != nil, "forget(where:) keeps non-matching keys")
        expect(bounded.record(for: 98) == nil, "forget(where:) drops matching keys")
        bounded.forget(key: 99)
        expect(bounded.record(for: 99) == nil, "forget(key:) drops that key")
    }

    // MARK: - Fuzz

    /// 随机扫描各类显示器/窗口/gap/循环/step 组合，断言不产生非法几何、非确定结果或重复漂移。
    static func testFuzz() {
        let displays: [[WindowPlacementEngine.Screen]] = [
            [mainScreen],
            [
                mainScreen,
                WindowPlacementEngine.Screen(
                    id: 2, frame: CGRect(x: 1440, y: -200, width: 2560, height: 1440),
                    visibleFrame: CGRect(x: 1440, y: -175, width: 2560, height: 1390))
            ],
            [
                WindowPlacementEngine.Screen(
                    id: 5, frame: CGRect(x: 0, y: 0, width: 1024, height: 640),
                    visibleFrame: CGRect(x: 0, y: 25, width: 1024, height: 590)),
                WindowPlacementEngine.Screen(
                    id: 6, frame: CGRect(x: -3840, y: 0, width: 3840, height: 2160),
                    visibleFrame: CGRect(x: -3840, y: 25, width: 3840, height: 2060))
            ]
        ]
        let windows: [CGRect] = [
            CGRect(x: 100, y: 100, width: 600, height: 400),
            CGRect(x: 0, y: 0, width: 0, height: 0),
            CGRect(x: -900, y: -900, width: 200, height: 150),
            CGRect(x: 200, y: 200, width: 5000, height: 4000),
            CGRect(x: 1439, y: 899, width: 1, height: 1)
        ]
        let gaps: [CGFloat] = [0, 1, 8, 25, 200]
        let cycles: [WindowCycle] = WindowCycle.allCases
        let steps = [0, 1, 5, -3]

        var checked = 0
        var problems: [String] = []
        for screens in displays {
            for window in windows {
                for gap in gaps {
                    for cycle in cycles {
                        for step in steps {
                            for command in WindowCommand.ID.allCases {
                                let input = WindowPlacementEngine.Input(
                                    command: command, windowFrame: window, screens: screens, gap: gap,
                                    step: step, cycle: cycle, restoreFrame: window, lastTileCommand: nil)
                                // placement 为 nil 是合法的静默空操作，不算失败。
                                guard let placement = WindowPlacementEngine.placement(for: input) else {
                                    continue
                                }
                                checked += 1
                                let rect = placement.frame
                                let label = "\(command.rawValue) gap \(gap) step \(step) window \(window)"

                                if !(rect.minX.isFinite && rect.minY.isFinite && rect.width.isFinite
                                    && rect.height.isFinite)
                                {
                                    problems.append("non-finite frame: \(label)")
                                }
                                if rect.width < 0 || rect.height < 0 {
                                    problems.append("negative size: \(label)")
                                }
                                guard let host = screens.first(where: { $0.id == placement.screenID })
                                else {
                                    problems.append("unknown screen id: \(label)")
                                    continue
                                }
                                if rect.intersection(host.visibleFrame).isNull {
                                    problems.append("off-screen frame: \(label)")
                                }
                                // 校验确定性，以及在第 0 步重复应用同一命令时不会漂移。
                                if WindowPlacementEngine.placement(for: input)?.frame != rect {
                                    problems.append("non-deterministic: \(label)")
                                }
                                var repeated = input
                                repeated.windowFrame = rect
                                // 只有第 0 步才应幂等：循环的存在本就是为了移动窗口。
                                if step == 0,
                                    let again = WindowPlacementEngine.placement(for: repeated)?.frame,
                                    command != .makeLarger, command != .makeSmaller, command != .moveLeft,
                                    command != .moveRight, command != .moveUp, command != .moveDown,
                                    command != .nextDisplay, command != .previousDisplay,
                                    again != rect
                                {
                                    problems.append("drifts on repeat: \(label) — \(rect) then \(again)")
                                }
                            }
                        }
                    }
                }
            }
        }
        expect(checked > 1000, "the fuzz sweep exercised a meaningful number of placements")
        expect(problems.isEmpty, "fuzz sweep found no violations")
        for problem in problems.prefix(10) { print("      \(problem)") }
    }
}
