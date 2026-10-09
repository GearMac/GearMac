// 文件职责：承载 Rooms 界面打开期间的状态——桌面快照读取一次，以及选择器的选中结果。
// 分层：Service（@Observable 状态容器）；@MainActor 隔离，AX 快照句柄不参与观察、不越过界面生命周期。
import Foundation

/// 某个 Rooms 界面打开期间的状态：桌面只读一次，以及选择器的选中结果。
@MainActor
@Observable
final class RoomSession {
    /// 房间未指定窗口就持有的应用：进入时打开，并保持可见。
    struct App: Hashable, Sendable {
        var bundleID: String
        var name: String
        var url: URL?
    }

    /// 待选中的房间成员之一，按房间顺序排列。
    enum Pick: Hashable, Sendable {
        case window(handle: Int)
        case app(App)
    }

    /// 一次扫描落定时自增，以便根据上次桌面绘制的预览被重绘。
    private(set) var revision = 0
    private(set) var isLoaded = false
    /// 选择器提供的所有窗口：可见窗口从前到后，然后是停泊、隐藏、最小化的窗口。
    private(set) var pickable: [RoomLiveWindow] = []
    private(set) var picked: [Pick] = []
    private(set) var editingID: UUID?
    /// 选择器的搜索框会过滤，因此房间名保存在这里。
    private(set) var roomName = ""
    /// 存活的 AX 句柄，因此从不被观察，也从不比界面存活更久。
    @ObservationIgnored private(set) var snapshot: RoomWindowSweep.Snapshot?

    /// 用一次新的扫描结果刷新可选窗口列表与版本号。
    func present(_ snapshot: RoomWindowSweep.Snapshot, parked: Set<UInt32>) {
        self.snapshot = snapshot
        pickable = snapshot.windows.sorted { lhs, rhs in
            let left = Self.pickingTier(lhs, parked: parked)
            let right = Self.pickingTier(rhs, parked: parked)
            return left != right ? left < right : (lhs.frontRank, lhs.handle) < (rhs.frontRank, rhs.handle)
        }
        isLoaded = true
        revision &+= 1
    }

    /// 开始一次选择：设定房间名、正在编辑的 id 与已选成员。
    func beginPicking(named name: String, editing id: UUID?, picked picks: [Pick]) {
        roomName = name
        editingID = id
        picked = picks
    }

    /// 切换一个成员的选中状态。
    func togglePick(_ pick: Pick) {
        if let index = picked.firstIndex(of: pick) {
            picked.remove(at: index)
        } else {
            picked.append(pick)
        }
    }

    /// 清空本次会话的全部状态。
    func reset() {
        snapshot = nil
        pickable = []
        picked = []
        editingID = nil
        roomName = ""
        isLoaded = false
    }

    private static func pickingTier(_ window: RoomLiveWindow, parked: Set<UInt32>) -> Int {
        if window.isAppHidden || window.isMinimized { return 2 }
        return window.windowID.map(parked.contains) == true ? 1 : 0
    }
}
