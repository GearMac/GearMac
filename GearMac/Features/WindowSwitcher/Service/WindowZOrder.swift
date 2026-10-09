// 文件职责：从窗口服务器读取每个 App 的隐式前后层级（z-order）排名，用于窗口切换器的最近使用排序。
// 分层：Service（@MainActor）；只读窗口层级信息，不读取窗口名，因此无需屏幕录制权限。
import CoreGraphics

/// 每个 App 最近处于前台的程度，来自窗口服务器自身的由前到后列表。
@MainActor
enum WindowZOrder {
    /// 层级 0 为普通窗口层；其上的任何层级都是菜单栏、Dock 或浮层面板。
    private static let normalLayer = 0

    /// App 的排名即其最前窗口所处的位置；从不读取 `kCGWindowName`，
    /// 因此该列表无需屏幕录制权限。
    static func appRanks() -> [pid_t: Int] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let listing = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else { return [:] }
        var ranks: [pid_t: Int] = [:]
        for window in listing {
            guard window[kCGWindowLayer as String] as? Int == normalLayer,
                let pid = window[kCGWindowOwnerPID as String] as? pid_t
            else { continue }
            if ranks[pid] == nil { ranks[pid] = ranks.count }
        }
        return ranks
    }
}
