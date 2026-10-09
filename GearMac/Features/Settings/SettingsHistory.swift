// 文件职责：设置页导航历史的纯状态机（后退/前进栈）。
// 分层：Settings（Model）；选择新页面会截断前进栈，重复选择当前页面不算一次移动。
/// 浏览器式语义：选择某个页面会截断它之后的前进历史，而重复选择当前页面不算一次移动。
struct SettingsHistory {
    private(set) var current: SettingsTab
    private var back: [SettingsTab] = []
    private var forward: [SettingsTab] = []

    init(current: SettingsTab) {
        self.current = current
    }

    var canGoBack: Bool { !back.isEmpty }
    var canGoForward: Bool { !forward.isEmpty }

    /// 切换到目标页面：当前页面压入后退栈，前进栈清空。
    mutating func select(_ tab: SettingsTab) {
        guard tab != current else { return }
        back.append(current)
        forward.removeAll()
        current = tab
    }

    /// 后退一步，把当前页面推入前进栈。
    mutating func goBack() {
        guard let previous = back.popLast() else { return }
        forward.append(current)
        current = previous
    }

    /// 前进一步，把当前页面推入后退栈。
    mutating func goForward() {
        guard let next = forward.popLast() else { return }
        back.append(current)
        current = next
    }
}
