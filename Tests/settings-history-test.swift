// 文件职责：SettingsHistory/SettingsNavigationState（设置面板导航与滚动揭示状态）的独立测试 harness，验证历史前进后退、侧栏分组与目录覆盖、搜索结果与排名，以及揭示请求与闪烁状态。
// 分层：测试 harness；纯状态机断言，无 UI 依赖。
import Foundation

/// 编译发布版 `SettingsHistory`，确保新增面板不会改变导航行为。
@main
@MainActor
struct SettingsHistoryTests {
    static var failures = 0
    static var passes = 0

    /// 断言：条件为真则计入通过，否则计为失败并打印消息。
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() {
        startsEmpty()
        selectingPushes()
        reselectingIsNotANavigation()
        roundTrips()
        aNewBranchDiscardsTheOldOne()
        clampsAtBothEnds()
        sidebarCoversEveryPane()
        sidebarIdentityNamespacesAreDisjoint()
        catalogCoversEveryPane()
        catalogIdentitiesAreUnique()
        catalogFindsKnownRows()
        catalogRanksTitlesFirst()
        catalogAnchorsMatchTheirPane()
        revealingRecordsANewRequestEachTime()
        flashOutlivesThePaneThatLitIt()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    /// 新建的历史不能前进也不能后退。
    static func startsEmpty() {
        let history = SettingsHistory(current: .general)
        expect(!history.canGoBack, "and has nowhere to go back to")
        expect(!history.canGoForward, "or forward to")
    }

    /// 选中新面板会把它压入历史，并留下可回退的位置。
    static func selectingPushes() {
        var history = SettingsHistory(current: .general)
        history.select(.clipboard)
        expect(history.current == .clipboard, "selecting shows the new pane")
        expect(history.canGoBack, "and leaves the old one behind us")
        expect(!history.canGoForward, "with nothing ahead")
    }

    /// 重复选中同一项不得堆叠记录，否则 Back 会在同一个面板上反复回退。
    static func reselectingIsNotANavigation() {
        var history = SettingsHistory(current: .general)
        history.select(.general)
        expect(!history.canGoBack, "re-selecting the current pane pushes nothing")

        history.select(.backup)
        history.select(.backup)
        history.goBack()
        expect(history.current == .general, "and one Back still reaches the pane before it")
    }

    /// 前进后退能沿同一路径往返，并在两端停住。
    static func roundTrips() {
        var history = SettingsHistory(current: .general)
        history.select(.snippets)
        history.select(.emoji)

        history.goBack()
        expect(history.current == .snippets, "Back walks one entry at a time")
        expect(history.canGoForward, "and what we left becomes reachable again")

        history.goBack()
        expect(history.current == .general, "Back reaches the pane we opened on")

        history.goForward()
        history.goForward()
        expect(history.current == .emoji, "Forward retraces the same path")
        expect(!history.canGoForward, "and stops where we had got to")
    }

    /// 回退后再选中会丢弃原来的前进分支。
    static func aNewBranchDiscardsTheOldOne() {
        var history = SettingsHistory(current: .general)
        history.select(.snippets)
        history.select(.emoji)
        history.goBack()
        history.goBack()

        history.select(.about)
        expect(history.current == .about, "selecting after going back moves there")
        expect(!history.canGoForward, "and drops the branch we had backed out of")

        history.goBack()
        expect(history.current == .general, "while Back still reaches where we branched from")
    }

    /// 在两端继续前进/后退都为空操作。
    static func clampsAtBothEnds() {
        var history = SettingsHistory(current: .general)
        history.goBack()
        expect(history.current == .general, "Back at the start is a no-op")
        history.goForward()
        expect(history.current == .general, "Forward with nothing ahead is a no-op")

        history.select(.about)
        history.goForward()
        expect(history.current == .about, "Forward at the tip is a no-op too")
    }

    // MARK: - Sidebar taxonomy
    // 侧栏按分组渲染，因此未归入任何分组的面板虽仍能编译却不可达。

    /// 每个面板恰好出现在一个侧栏分组中。
    static func sidebarCoversEveryPane() {
        let grouped = SettingsSection.allCases.flatMap(\.tabs)
        expect(
            Set(grouped) == Set(SettingsTab.allCases),
            "every pane appears in exactly one sidebar group")
        expect(grouped.count == SettingsTab.allCases.count, "and none appears twice")
    }

    /// 可选择的 `List` 会把分区与行的 ID 压平到同一个命名空间。
    static func sidebarIdentityNamespacesAreDisjoint() {
        let sections = Set(SettingsSection.allCases.map { AnyHashable($0.id) })
        let tabs = Set(SettingsTab.allCases.map { AnyHashable($0.id) })
        expect(
            sections.isDisjoint(with: tabs),
            "no sidebar group shares an identity with a pane")
        expect(tabs.count == SettingsTab.allCases.count, "and every pane's identity is its own")
    }

    // MARK: - Search catalog
    // `Form` 无法被询问自己包含哪些行，因此目录是手写的，可能发生漂移。

    /// 每个面板都能从设置搜索到达。
    static func catalogCoversEveryPane() {
        let covered = Set(SettingsSearchCatalog.entries.map(\.tab))
        expect(
            covered == Set(SettingsTab.allCases),
            "every pane is reachable from Settings search")
    }

    /// 结果 `List` 以 `id` 为键；重复的 id 会让两行被当作同一行选中。
    static func catalogIdentitiesAreUnique() {
        let ids = SettingsSearchCatalog.entries.map(\.id)
        expect(Set(ids).count == ids.count, "no two catalog entries share an identity")
    }

    /// 已知关键词能命中对应面板。
    static func catalogFindsKnownRows() {
        let cases: [(String, SettingsTab)] = [
            ("hyper", .general),
            ("caps lock", .general),
            ("launch at login", .general),
            ("automatically check for updates", .general),
            ("popup", .general),
            ("paste history", .clipboard),
            ("window manage", .windowManagement),
            ("skin tone", .emoji),
            ("mcp", .ai)
        ]
        for (query, tab) in cases {
            let found = SettingsSearchCatalog.results(for: query).first
            expect(found?.tab == tab, "“\(query)” lands on \(tab.title)")
        }
    }

    /// anchor 自带面板信息，因此不会把某行写错到别的面板下。
    static func catalogAnchorsMatchTheirPane() {
        for entry in SettingsSearchCatalog.entries {
            guard let anchor = entry.anchor else { continue }
            expect(anchor.tab == entry.tab, "“\(entry.title)” is filed under its anchor's pane")
        }
        let panes = SettingsSearchCatalog.entries.filter { $0.anchor == nil }.map(\.tab)
        expect(Set(panes).count == panes.count, "and each pane is listed as a result exactly once")
    }

    /// 命中标题的词必须胜过仅在面包屑中命中的同一个词。
    static func catalogRanksTitlesFirst() {
        let results = SettingsSearchCatalog.results(for: "extensions")
        expect(results.first?.tab == .extensions, "“extensions” opens on its own pane")
        expect(
            SettingsSearchCatalog.results(for: "nothing here matches at all").isEmpty,
            "and an unmatched query returns nothing")
    }

    // MARK: - Revealing a section

    /// 两次选中同一结果必须各自触发滚动与脉冲，而不是判定相等后什么都不做。
    static func revealingRecordsANewRequestEachTime() {
        let navigation = SettingsNavigationState(tab: .general)
        expect(navigation.scrollRequest == nil, "a fresh window has nothing to reveal")

        navigation.select(.clipboard)
        expect(navigation.scrollRequest == nil, "and a plain pane selection asks for no scroll")

        navigation.select(.general, revealing: .section(.generalHyperKey))
        let first = navigation.scrollRequest
        expect(first?.target == .section(.generalHyperKey), "a result records what it wants revealed")
        expect(navigation.tab == .general, "and navigates to that section's pane")

        navigation.select(.general, revealing: .section(.generalHyperKey))
        expect(navigation.scrollRequest != first, "asking twice is two distinct requests")

        // 已过期的请求不得清除取代它的那个请求。
        if let first { navigation.clear(first) }
        expect(navigation.scrollRequest != nil, "clearing a superseded request is a no-op")
        if let live = navigation.scrollRequest { navigation.clear(live) }
        expect(navigation.scrollRequest == nil, "clearing the live one releases it")
    }

    /// 脉冲的存活时间长于触发它的面板，且只有它自己的发起者才能将其熄灭。
    static func flashOutlivesThePaneThatLitIt() {
        let navigation = SettingsNavigationState(tab: .general)
        navigation.select(.clipboard, revealing: .row(.clipboardHistory, "Keep history for"))
        navigation.beginFlash(.row(.clipboardHistory, "Keep history for"))
        expect(navigation.flashing == .row(.clipboardHistory, "Keep history for"), "the revealed row is lit")

        navigation.endFlash(.section(.generalHyperKey))
        expect(navigation.flashing != nil, "another target can't put it out")
        navigation.endFlash(.row(.clipboardHistory, "Keep history for"))
        expect(navigation.flashing == nil, "its own owner can")

        // 跳转到别处时，不得让旧的高亮还在后面亮着。
        navigation.beginFlash(.row(.clipboardHistory, "Keep history for"))
        navigation.select(.general)
        expect(navigation.flashing == nil, "navigating away clears a stale pulse")
    }
}
