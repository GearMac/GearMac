// 文件职责：以独立可执行 harness 验证窗口切换条目的标识、显示标题、搜索字段映射、排序与查询排序。
// 分层：测试 harness；独立可执行（@main），仅依赖 Foundation，不 import AppKit/SwiftUI，只读取被测类型。
import Foundation

@main
@MainActor
struct WindowSwitchTests {
    static var failures = 0

    /// 断言辅助：条件为假时累计失败并打印 FAIL 信息。
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    /// 构造一个窗口切换条目，测试夹具。
    static func entry(
        _ handle: Int, app: String = "Safari", title: String = "Window",
        minimized: Bool = false, rank: Int = 0
    ) -> WindowSwitchEntry {
        WindowSwitchEntry(
            handle: handle, appName: app, bundleID: "com.example.\(app.lowercased())",
            iconURL: nil, iconStamp: 0, title: title, isMinimized: minimized, appRank: rank)
    }

    /// harness 入口：依次运行全部用例，失败时以退出码 1 结束。
    static func main() {
        identity()
        displayTitle()
        searchMapping()
        ordering()
        orderingIsTotal()
        ranking()
        rankingLimit()

        print(failures == 0 ? "Window switch tests passed" : "\(failures) window switch tests failed")
        exit(failures == 0 ? 0 : 1)
    }

    /// 条目标识：id 取窗口句柄，在单次扫描内唯一。
    static func identity() {
        expect(entry(7).id == "7", "the id is the handle, which is unique inside one sweep")
    }

    /// 显示标题：有标题时用标题，标题为空或全空白时回退为应用名。
    static func displayTitle() {
        expect(entry(0, title: "Notes.md").displayTitle == "Notes.md", "a titled window shows it")
        expect(
            entry(0, app: "Preview", title: "").displayTitle == "Preview",
            "an untitled window reads as its app rather than as a blank row")
        expect(
            entry(0, app: "Preview", title: "   ").displayTitle == "Preview",
            "a whitespace-only title is no title")
    }

    /// 搜索字段映射：窗口标题作为 name，应用名作为 owner 供查询匹配。
    static func searchMapping() {
        let aliases = entry(0, app: "Safari", title: "Inbox").searchFields().aliases
        expect(
            aliases.contains { $0.text == "Inbox" && $0.role == .name },
            "the window title is the name a query matches")
        expect(
            aliases.contains { $0.text == "Safari" && $0.role == .owner },
            "the app rides as owner: every window of one app shares it")
    }

    /// 排序：前台应用优先，其次按应用排名，未排名随后，最小化窗口排最后。
    static func ordering() {
        let sorted = WindowSwitchOrder.sorted([
            entry(0, app: "Mail", rank: 2),
            entry(1, app: "Safari", minimized: true, rank: 0),
            entry(2, app: "Safari", rank: 0),
            entry(3, app: "Safari", rank: 0),
            entry(4, app: "Zed", rank: .max)
        ])
        expect(
            sorted.map(\.handle) == [2, 3, 0, 4, 1],
            "front app first, then by rank, unranked next, minimized last: \(sorted.map(\.handle))")
    }

    /// 排序是全域的：打乱输入得到相同结果，不丢条目，且最小化窗口连续位于末尾。
    static func orderingIsTotal() {
        let entries = (0..<12).map {
            entry($0, app: ["Mail", "Safari", "Zed"][$0 % 3], minimized: $0 % 4 == 0, rank: $0 % 3)
        }
        let once = WindowSwitchOrder.sorted(entries)
        let twice = WindowSwitchOrder.sorted(entries.reversed())
        expect(
            once.map(\.handle) == twice.map(\.handle),
            "the order is total, so a shuffled sweep sorts identically")
        expect(
            once.map(\.handle).sorted() == entries.map(\.handle).sorted(),
            "sorting drops nothing")
        let split = once.firstIndex(where: \.isMinimized) ?? once.count
        expect(
            once[split...].allSatisfy(\.isMinimized),
            "minimized windows form one run at the end, never interleaved")
    }

    /// 查询排序：空查询保持传入顺序，完全匹配优先，应用名命中其全部窗口。
    static func ranking() {
        let entries = [
            entry(0, app: "Mail", title: "Drafts"),
            entry(1, app: "Safari", title: "Inbox"),
            entry(2, app: "Safari", title: "Inbox archive")
        ]
        expect(
            WindowSwitchQuery.rank(entries, for: "").map(\.handle) == [0, 1, 2],
            "an empty query keeps the order it was handed")
        expect(
            WindowSwitchQuery.rank(entries, for: "Inbox").first?.handle == 1,
            "the exact title beats the one that only starts with it")
        expect(
            WindowSwitchQuery.rank(entries, for: "Safari").map(\.handle) == [1, 2],
            "the app name matches every one of its windows, in the order given")
        expect(
            WindowSwitchQuery.rank(entries, for: "zzz").isEmpty,
            "a query nothing matches ranks nothing")
    }

    /// 结果上限：空查询与全匹配查询都受 resultLimit 限制。
    static func rankingLimit() {
        let entries = (0..<(WindowSwitchQuery.resultLimit + 50)).map {
            entry($0, app: "Safari", title: "Tab \($0)")
        }
        expect(
            WindowSwitchQuery.rank(entries, for: "").count == WindowSwitchQuery.resultLimit,
            "an empty query is capped too, so a huge sweep never builds a huge list")
        expect(
            WindowSwitchQuery.rank(entries, for: "Tab").count == WindowSwitchQuery.resultLimit,
            "the cap holds under a query every row matches")
    }
}
