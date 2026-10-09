// 文件职责：窗口切换器的条目模型，描述一个可切换的已打开窗口（句柄、标题、图标、层级等）。
// 分层：Model；纯数据结构，不 import AppKit，仅用句柄标识窗口以保持无副作用。
import Foundation

/// 切换器提供的一个已打开窗口。使用句柄而非 `AXUIElement`：该分层保持纯净。
struct WindowSwitchEntry: Identifiable, Hashable, Sendable {
    /// App 自身的由前到后顺序，跨 App 展平；同时用于索引实际元素。
    let handle: Int
    let appName: String
    let bundleID: String
    let iconURL: URL?
    let iconStamp: Int
    let title: String
    let isMinimized: Bool
    /// 值越小越靠前；当 App 没有屏幕上的窗口可作排序依据时为 `.max`。
    let appRank: Int

    /// 使用字符串，因为每个调色板列表都以字符串标识其行。
    var id: String { String(handle) }

    /// 尚无标题的文档窗口显示为其 App 名，而不是空白行。
    var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? appName : title
    }

    // App 名以 owner 身份参与搜索而非 name：同一 App 的所有窗口共享它。
    func searchFields() -> SearchFields {
        [SearchAlias.name(displayTitle), SearchAlias.owner(appName)]
    }
}
