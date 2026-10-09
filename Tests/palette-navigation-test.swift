// 文件职责：验证命令面板的导航栈语义：push/pop/replace/prepare/ring hop 后屏幕、查询与选中行是否按预期恢复。
// 分层：测试 harness；仅依赖 Foundation，直接驱动 PaletteState，不引入 AppKit。
import Foundation

/// 返回必须表现得像从未离开：同一屏幕、同一查询、同一行。
@main
@MainActor
struct PaletteNavigationTests {
    static var failures = 0
    static var passes = 0

    /// 断言导航行为符合预期，不符时计为失败并打印失败信息。
    static func expect(_ condition: Bool, _ message: String) {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    /// 一个已输入搜索词的启动器，这正是返回步骤必须还原的状态。
    static func searchingLauncher() -> PaletteState {
        let vm = PaletteState()
        vm.prepare(mode: .launcher)
        vm.query = "clipboard"
        vm.selection = 3
        return vm
    }

    static func main() {
        let vm = searchingLauncher()
        expect(!vm.canGoBack, "a prepared screen is a root with nothing behind it")

        vm.push(mode: .clipboard)
        expect(
            vm.mode == .clipboard && vm.query.isEmpty && vm.selection == 0,
            "a pushed screen opens as fresh as a prepared one")
        expect(vm.canGoBack, "the screen it was pushed over is still there to return to")

        vm.emojiCategoryFilter = .pinned
        vm.emojiGridColumnsOverride = .six

        expect(vm.pop(), "a pushed screen has a step back")
        expect(
            vm.mode == .launcher && vm.query == "clipboard" && vm.selection == 3,
            "the back step restores the screen, its query and its selection")
        expect(!vm.canGoBack, "the restored screen is the root again")
        expect(!vm.pop(), "a root has nowhere left to go")
        expect(
            vm.mode == .launcher && vm.query == "clipboard",
            "a refused back step leaves the screen untouched")

        let freshEmoji = searchingLauncher()
        freshEmoji.emojiCategoryFilter = .category(.flags)
        freshEmoji.emojiGridColumnsOverride = .ten
        freshEmoji.prepare(mode: .emoji)
        expect(
            freshEmoji.emojiCategoryFilter == .all && freshEmoji.emojiGridColumnsOverride == nil,
            "a fresh emoji screen restores all categories and the configured grid default")

        // 列表若被吸附到顶部，就会丢掉正要恢复的那个选中项。
        let tokens = searchingLauncher()
        tokens.push(mode: .emoji)
        let reset = tokens.resetToken
        let follow = tokens.followToken
        expect(tokens.pop(), "the emoji screen goes back to the launcher")
        expect(tokens.resetToken == reset, "a back step does not snap the restored list to the top")
        expect(tokens.followToken != follow, "it scrolls the restored row into view instead")

        let nested = searchingLauncher()
        nested.push(mode: .ai)
        nested.query = "why is the sky blue"
        nested.push(mode: .aiHistory)
        expect(
            nested.pop() && nested.mode == .ai && nested.query == "why is the sky blue",
            "history returns to the chat draft it was opened over")
        expect(
            nested.pop() && nested.mode == .launcher && nested.query == "clipboard",
            "and chat returns to the search that found it")

        // `replace` 用于屏幕替换自身内容，这不算一次独立的入栈步骤。
        let replaced = searchingLauncher()
        replaced.push(mode: .ai)
        replaced.replace(mode: .ai)
        expect(replaced.canGoBack, "starting a new chat keeps whatever chat was opened over")
        expect(
            replaced.pop() && replaced.mode == .launcher,
            "so one back step still lands on the launcher")

        let summoned = searchingLauncher()
        summoned.push(mode: .clipboard)
        summoned.prepare(mode: .emoji)
        expect(!summoned.canGoBack, "a summon is a new root, not a step onto the old stack")

        let ringed = searchingLauncher()
        ringed.push(mode: .clipboard)
        ringed.resetNavigation()
        expect(
            !ringed.canGoBack && ringed.mode == .clipboard,
            "closing the Tab ring drops the stack without disturbing the screen")

        let hopped = searchingLauncher()
        hopped.pushCarryingQuery(mode: .clipboard)
        expect(
            hopped.mode == .clipboard && hopped.query == "clipboard" && hopped.selection == 3,
            "a ring hop carries the query and the row it was on")
        expect(
            hopped.pop() && hopped.mode == .launcher && hopped.query == "clipboard",
            "and the screen it crossed from is the step back")

        let chatted = searchingLauncher()
        chatted.push(mode: .ai)
        chatted.query = "why is the sky blue"
        chatted.push(mode: .clipboard)
        expect(
            chatted.pop() && chatted.mode == .ai && chatted.query == "why is the sky blue",
            "Tab out of chat leaves the draft to come back to")
        expect(
            chatted.pop() && chatted.mode == .launcher,
            "and a second step back reaches the launcher the ring started on")

        let pasted = searchingLauncher()
        pasted.query = "\nfirst pasted row,\r\nsecond pasted row\u{2028}third\n"
        expect(
            pasted.collapseQueryLineBreaks() && pasted.query == "first pasted row, second pasted row third",
            "a multi-line paste collapses to one line with no edge breaks")
        expect(
            !pasted.collapseQueryLineBreaks() && pasted.query == "first pasted row, second pasted row third",
            "a single-line query is left alone")

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
