// 文件职责：房间选择器（RoomPicker）的列表视图，渲染窗口/App 行并展示其房间序号与选中态。
// 分层：UI（SwiftUI 视图）；仅负责展示与交互回调，不持有业务状态。
import SwiftUI

/// 房间选择器的列表：可滚动、跟随选中项，并将点击回调交给上层。
struct RoomPickerList: View {
    @Environment(\.metrics) private var metrics
    let rows: [RoomPickerRow]
    /// 房间顺序；成员的序号即其索引加一。
    let picked: [RoomSession.Pick]
    let selectedID: String?
    let scroll: ScrollIntent
    let onActivate: (RoomPickerRow) -> Void

    private var firstRowSelected: Bool { selectedID != nil && selectedID == rows.first?.id }

    /// 列表主体：渲染所有行，应用选中样式与滚动跟随。
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        RoomPickerRowView(
                            row: row, place: picked.firstIndex(of: row.pick).map { $0 + 1 },
                            selected: row.id == selectedID
                        )
                        .selectionFrame(row.id == selectedID)
                        .contentShape(Rectangle())
                        .onTapGesture { onActivate(row) }
                    }
                }
                .padding(.horizontal, metrics.spacing.md)
                .padding(.vertical, metrics.spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .scrollFollowsSelection(scroll, row: selectedID, atOrigin: firstRowSelected, proxy: proxy)
        }
    }
}

/// 选择器中的单行视图：展示应用图标、标题、尾部说明与房间序号徽标。
private struct RoomPickerRowView: View {
    @Environment(\.metrics) private var metrics
    @Environment(AppSettings.self) private var settings
    let row: RoomPickerRow
    /// 它在房间中的序号，1 表示主窗口；不在房间中时为 nil。
    let place: Int?
    let selected: Bool
    @State private var hovered = false

    /// 行背景色：选中 > 悬停 > 透明。
    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    /// 行主标题：窗口标题为空时回退为应用名，App 行直接使用其名称。
    private var title: String {
        switch row {
        case .window(let window):
            window.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? window.appName : window.title
        case .app(let app):
            app.name
        }
    }

    /// 行尾部说明：应用名，或窗口已隐藏/已最小化的状态。
    private var trailing: String {
        switch row {
        case .window(let window):
            if window.isAppHidden {
                return String(format: settings.text(WindowKey.pickerListHidden), window.appName)
            }
            if window.isMinimized {
                return String(format: settings.text(WindowKey.pickerListMinimized), window.appName)
            }
            return window.appName
        case .app:
            return settings.text(WindowKey.pickerListAppOpensWithRoom)
        }
    }

    /// 需要显示图标的应用 URL（窗口行取窗口所属 App，App 行取自身）。
    private var appURL: URL? {
        switch row {
        case .window(let window): window.appURL
        case .app(let app): app.url
        }
    }

    /// 行主体：徽标 + 图标 + 标题 + 尾部文字，并设置无障碍信息。
    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            badge
            Group {
                if let appURL {
                    EntryIconView(source: .file(stamp: FileIconStamp.value(for: appURL)), fileURL: appURL)
                } else {
                    EntryIconView(source: .symbol("macwindow"))
                }
            }
            .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
            Text(title)
                .font(metrics.typography.rowTitle)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: metrics.spacing.md)
            Text(trailing)
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous).fill(fill)
        )
        .armedHover($hovered)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(
            place.map {
                String(
                    format: settings.text(WindowKey.pickerListAccessibilityPlace), trailing, $0)
            } ?? trailing)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// 左侧序号徽标：未在房间中显示空心圆，在房间中显示实心圆加序号。
    private var badge: some View {
        ZStack {
            Circle()
                .strokeBorder(place == nil ? Theme.Colors.cardStroke : .clear, lineWidth: 1)
                .background(Circle().fill(place == nil ? .clear : Theme.Colors.roomCardStroke))
            if let place {
                Text("\(place)")
                    .font(metrics.typography.rowTrailing.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
    }
}
