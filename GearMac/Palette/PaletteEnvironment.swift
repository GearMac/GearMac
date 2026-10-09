// 文件职责：把 AppCore 及其各项状态注入 SwiftUI 环境，供调色板与 ⌘K 菜单共享同一套依赖。
// 分层：UI（SwiftUI）；`InterfaceMetricsScope` 通过 body 重读，避免环境值在建面板时被冻结。
import SwiftUI

/// 存储型环境值会在建面板时被冻结；修饰符在 body 中重读即可随 Observation 更新。
private struct InterfaceMetricsScope: ViewModifier {
    let settings: AppSettings

    func body(content: Content) -> some View {
        content.environment(\.metrics, settings.interfaceSize.metrics)
    }
}

extension View {
    /// 共享注入，使 ⌘K 菜单自己的宿主视图层级不会与调色板不一致。
    func paletteEnvironment(_ core: AppCore) -> some View {
        self
            .modifier(InterfaceMetricsScope(settings: core.settings))
            .environment(core)
            .environment(core.settings)
            .environment(core.palette)
            .environment(core.appIndex)
            .environment(core.clipboardStore)
            .environment(core.favorites)
            .environment(core.visibility)
            .environment(core.aliases)
            .environment(core.fallbacks)
            .environment(core.calcHistory)
            .environment(core.currencyRates)
            .environment(core.emojiIndex)
            .environment(core.frequentEmoji)
            .environment(core.fileSearch)
            .environment(core.dictionary)
            .environment(core.menuSearch)
            .environment(core.windowSwitch)
            .environment(core.runningApps)
            .environment(core.hotKeys)
            .environment(core.uninstall)
            .environment(core.quicklinks)
            .environment(core.snippetsStore)
            .environment(core.extensions)
            .environment(core.calendarStore)
            .environment(core.meetingClock)
    }
}
