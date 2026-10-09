// 文件职责：定义设置页的滚动锚点与搜索高亮（药丸）效果，支撑「搜索结果滚动并闪烁」的交互。
// 分层：UI（SwiftUI 修饰器）；锚点由 SettingsAnchor 命名，闪烁状态来自导航会话。
import SwiftUI

extension View {
    /// 设置页的 `Form`：让搜索结果将其中某个分区滚动到可见位置并高亮它。
    /// 这里由页面自己声明所属 tab，因为切换过程中两个页面会短暂同时存在，
    /// 而那时 `navigation.tab` 已经指向新的页面。
    func settingsScrollTarget(_ tab: SettingsTab) -> some View {
        modifier(SettingsScrollTarget(tab: tab))
    }

    /// 自身没有标题的 `Section`：仍可作为结果滚动到的位置，只是没有高亮可绘制。
    /// 所有*有*标题的分区都改用 `SettingsSectionHeader`。
    func settingsAnchor(_ anchor: SettingsAnchor) -> some View {
        id(SettingsTarget.section(anchor))
    }
}

/// 搜索结果到达时留下的高亮：仅在命中的名称后面画一个药丸背景，不画其他东西。
/// `Form` 会把 `.background` 应用到整行的*内容*框上，因此给整行或整个分区加高亮
/// 会在其中每个标签、按钮和脚注段落周围画出参差不齐的色块。
private struct SearchPill: ViewModifier {
    let target: SettingsTarget
    @Environment(SettingsNavigationState.self) private var navigation

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xxs)
            .background(
                Capsule().fill(navigation.flashing == target ? Theme.Colors.searchFlash : .clear)
            )
            // 把内边距还回去，这样药丸自身的内边距不会让标签偏离所在行的边缘。
            .padding(.horizontal, -Theme.Spacing.sm)
            .padding(.vertical, -Theme.Spacing.xxs)
            .id(target)
    }
}

/// `Section` 的名称，同时也是命中整个分组的结果的落点。
struct SettingsSectionHeader<Label: View>: View {
    let anchor: SettingsAnchor
    @ViewBuilder var label: Label

    var body: some View {
        label.modifier(SearchPill(target: .section(anchor)))
    }
}

extension SettingsSectionHeader where Label == Text {
    /// 标题取自锚点，因此分区名称与它的搜索面包屑是同一个字符串。
    init(_ anchor: SettingsAnchor) {
        self.init(anchor: anchor) { Text(anchor.title) }
    }
}

/// 单项设置自身的名称，用来替代行标签原本持有的 `Text`。它正是行级搜索结果
/// 滚动到并高亮的目标。
struct SettingsRowTitle: View {
    let anchor: SettingsAnchor
    let title: String

    init(_ anchor: SettingsAnchor, _ title: String) {
        self.anchor = anchor
        self.title = title
    }

    var body: some View {
        Text(title).modifier(SearchPill(target: .row(anchor, title)))
    }
}

/// 让设置页的 Form 响应滚动请求、滚动到锚点并闪烁的修饰器。
private struct SettingsScrollTarget: ViewModifier {
    let tab: SettingsTab
    @Environment(SettingsNavigationState.self) private var navigation

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                // 以请求为 task 标识，因此第二次跳转会在第一次高亮尚未结束时取消它。
                .task(id: navigation.scrollRequest) { await reveal(with: proxy) }
        }
    }

    /// 滚动到请求的锚点、触发高亮，并在高亮结束后清除请求。
    private func reveal(with proxy: ScrollViewProxy) async {
        guard let request = navigation.scrollRequest, request.target.tab == tab else { return }
        // 该页面可能刚刚挂载，因此先让它的 `Form` 完成锚点布局再滚动。
        await Task.yield()
        withAnimation(.easeOut(duration: Theme.Duration.settingsReveal)) {
            proxy.scrollTo(request.target, anchor: .center)
        }
        navigation.beginFlash(request.target)
        // 被取消说明之后的跳转取代了本次，高亮现在归后者所有。
        do {
            try await Task.sleep(for: .seconds(Theme.Duration.settingsFlash))
        } catch {
            return
        }
        withAnimation(.easeOut(duration: Theme.Duration.settingsFlashOut)) {
            navigation.endFlash(request.target)
        }
        // 最后才清除：它作为本任务的标识，过早清除会取消这次显示动作本身。
        navigation.clear(request)
    }
}
