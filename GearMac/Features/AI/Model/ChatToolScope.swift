// 文件职责：描述单次会话可调用的 MCP 服务器范围，记录被关闭的服务器 slug。
// 分层：Model；纯值类型，仅表达会话级工具开关状态。
import Foundation

/// 一次会话可调用的 MCP 服务器范围；由输入框的工具菜单编辑。
struct ChatToolScope: Equatable, Sendable {
    var isEnabled = true
    /// 本次会话按 slug 关闭的服务器；之后新增的服务器默认开启。
    var excluded: Set<String> = []

    /// 判断该 slug 的服务器当前是否允许调用。
    func allows(_ slug: String) -> Bool {
        isEnabled && !excluded.contains(slug)
    }

    /// 切换某台服务器的启用状态。
    mutating func toggle(_ slug: String) {
        if excluded.contains(slug) {
            excluded.remove(slug)
        } else {
            excluded.insert(slug)
        }
    }
}
