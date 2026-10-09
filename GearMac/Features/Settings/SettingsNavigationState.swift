// 文件职责：单个设置窗口的导航会话，包装导航历史，并向页面发出滚动/高亮请求。
// 分层：Settings（Model/会话状态）；只属于一个窗口，在窗口关闭时释放，历史不跨窗口存活。
import Observation

/// 不放在 `AppCore` 上：它是一个窗口的会话，在 `windowWillClose` 时释放，因此历史不会跨窗口存活。
@MainActor
@Observable
final class SettingsNavigationState {
    private var history: SettingsHistory
    private var requests = 0

    init(tab: SettingsTab) {
        history = SettingsHistory(current: tab)
    }

    var tab: SettingsTab { history.current }
    var canGoBack: Bool { history.canGoBack }
    var canGoForward: Bool { history.canGoForward }

    /// 由搜索结果设置，由负责滚动到该位置的页面消费。
    private(set) var scrollRequest: SettingsScrollRequest?
    /// 当前高亮的分区。整个窗口只有这一个来源，因此切换页面不会丢失它。
    private(set) var flashing: SettingsTarget?

    /// 搜索结果会导航并请求页面显示某个分区；侧边栏行只做导航。
    func select(_ tab: SettingsTab, revealing target: SettingsTarget? = nil) {
        history.select(tab)
        // 任何导航都会熄灭上一次的高亮，因此过期的高亮不会残留在已切换的页面上。
        flashing = nil
        guard let target else { return }
        requests += 1
        scrollRequest = SettingsScrollRequest(target: target, token: requests)
    }

    /// 开始高亮指定目标。
    func beginFlash(_ target: SettingsTarget) {
        flashing = target
    }

    /// 结束高亮；除非之后的跳转已经点亮了别处。
    func endFlash(_ target: SettingsTarget) {
        guard flashing == target else { return }
        flashing = nil
    }

    /// 只在高亮结束后才清除：它作为页面任务的标识，过早清除会取消正在执行显示动作的那个任务。
    func clear(_ request: SettingsScrollRequest) {
        guard scrollRequest == request else { return }
        scrollRequest = nil
    }

    func goBack() { history.goBack() }
    func goForward() { history.goForward() }
}
