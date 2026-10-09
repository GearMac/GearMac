// 文件职责：测试 fallback 列表的纯逻辑部分——身份标识、存储顺序，以及分区标题的省略处理。
// 分层：测试 harness；纯逻辑断言，不依赖 AppKit/SwiftUI，失败时以非零退出码结束。

import Foundation

/// fallback 列表纯逻辑的独立测试 harness（直接运行，不依赖 XCTest）。
@main
@MainActor
struct FallbackTests {
    static var failures = 0
    static var passes = 0

    /// 断言辅助：条件不成立时累加失败计数并打印明细。
    static func check(_ name: String, _ condition: Bool, _ detail: String = "") {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        }
    }

    /// harness 入口：依次运行各分组断言，打印统计，并在存在失败时以退出码 1 结束。
    static func main() {
        identity()
        ordering()
        headers()
        verbs()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Identity

    /// 校验 fallback 的 id 即其条目的 entry id，且可由 id 反查还原。
    static func identity() {
        // id 就是该行的 entry id，正因如此，存储的顺序才能指向仍然存在的行。
        for builtin in Fallback.Builtin.allCases {
            let fallback = Fallback.builtin(builtin)
            check(
                "\(builtin.rawValue) is its command's id", fallback.id == builtin.command.rawValue,
                "got \(fallback.id)")
            check(
                "\(builtin.rawValue) round-trips", Fallback(id: fallback.id) == fallback,
                "got \(String(describing: Fallback(id: fallback.id)))")
        }

        let quicklinkID = UUID()
        let quicklink = Fallback.quicklink(quicklinkID)
        check(
            "a quicklink's id is its entry id",
            quicklink.id == Quicklink.entryIDPrefix + quicklinkID.uuidString.lowercased(),
            "got \(quicklink.id)")
        check("a quicklink round-trips", Fallback(id: quicklink.id) == quicklink)

        // 每个内置项的 id 必须互不相同，否则会悄悄顶替掉另一个条目的存储位置。
        let ids = Set(Fallback.Builtin.allCases.map { Fallback.builtin($0).id })
        check("built-in ids are distinct", ids.count == Fallback.Builtin.allCases.count)

        // 自身没有 fallback 的命令不应被解析出 fallback。
        check("a plain command is not a fallback", Fallback(id: CommandID.about.rawValue) == nil)
        check("nonsense is not a fallback", Fallback(id: "banana") == nil)
        check("a bare uuid is not a fallback", Fallback(id: UUID().uuidString) == nil)
    }

    // MARK: - Ordering

    /// 校验存储顺序的恢复行为：排序、新增项置尾、失效 id 跳过。
    static func ordering() {
        let ai = Fallback.builtin(.quickAI)
        let files = Fallback.builtin(.searchFiles)
        let shell = Fallback.builtin(.runShellCommand)
        let link = Fallback.quicklink(UUID())

        check(
            "no stored order keeps the offered order",
            Fallback.ordered([ai, files, shell], by: []) == [ai, files, shell])

        check(
            "a stored order is honoured",
            Fallback.ordered([ai, files, shell], by: [shell.id, ai.id, files.id])
                == [shell, ai, files])

        // 在上次重排之后新建的 quicklink 必须落到末尾，而不能消失。
        check(
            "an unseen fallback lands last",
            Fallback.ordered([ai, link, files], by: [files.id, ai.id]) == [files, ai, link])

        // 已删除 quicklink 的 id 仍留在存储顺序中；它既不能复活，也不能挪动相邻项。
        check(
            "a stored id with nothing behind it is skipped",
            Fallback.ordered([ai, files], by: [link.id, files.id, ai.id]) == [files, ai])

        check("nothing available is nothing offered", Fallback.ordered([], by: [ai.id]).isEmpty)
    }

    // MARK: - Header

    /// 校验分区标题对查询串的引用与省略（截断）规则。
    static func headers() {
        check(
            "a short query is quoted whole",
            Fallback.sectionTitle(query: "todo") == "Use “todo” with…",
            "got \(Fallback.sectionTitle(query: "todo"))")

        let long = String(repeating: "a", count: 200)
        let title = Fallback.sectionTitle(query: long, limit: 20)
        // 省略的意义所在：标题仍须表明该分区是做什么的。
        check("a long query still ends in the verb", title.hasSuffix("” with…"), "got \(title)")
        check("a long query is elided", title.contains("…a"), "got \(title)")
        check("a long query is bounded by the limit", title.count <= 20 + 13, "got \(title.count)")

        // 边界判定为严格相等，因此长度恰好等于上限的查询串不会被改动。
        let exact = String(repeating: "b", count: 20)
        check(
            "a query at the limit is kept whole",
            Fallback.sectionTitle(query: exact, limit: 20) == "Use “\(exact)” with…")

        // 默认上限必须能容纳一个真实 URL，这正是当初据以设定该值的查询样例。
        let url = "https://github.com/vgnshiyer/py-apple-books.git"
        check(
            "the default limit keeps a repository URL whole",
            Fallback.sectionTitle(query: url) == "Use “\(url)” with…",
            "got \(Fallback.sectionTitle(query: url))")
    }

    // MARK: - Verbs

    /// 校验每个 fallback 都提供非空且互不相同的打开动词。
    static func verbs() {
        var verbs = Fallback.Builtin.allCases.map { Fallback.builtin($0).openVerb }
        verbs.append(Fallback.quicklink(UUID()).openVerb)
        check("every fallback names its own action", verbs.allSatisfy { !$0.isEmpty })
        check("the verbs are distinct", Set(verbs).count == verbs.count, "got \(verbs)")
    }
}
