// 文件职责：定义窗口切换器在空查询时的默认排序规则。
// 分层：Model；纯排序逻辑，不依赖 UI 或系统 API。
import Foundation

/// 空查询时显示的顺序：最近使用在前，最小化的窗口在最后。
enum WindowSwitchOrder {
    /// 全序排序，因此无论扫描以何种顺序枚举 App，排序结果都确定。
    static func sorted(_ entries: [WindowSwitchEntry]) -> [WindowSwitchEntry] {
        entries.sorted { left, right in
            if left.isMinimized != right.isMinimized { return right.isMinimized }
            if left.appRank != right.appRank { return left.appRank < right.appRank }
            if left.appName != right.appName {
                return left.appName.localizedCaseInsensitiveCompare(right.appName)
                    == .orderedAscending
            }
            return left.handle < right.handle
        }
    }
}
