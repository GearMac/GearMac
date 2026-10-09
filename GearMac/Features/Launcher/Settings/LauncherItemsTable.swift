// 文件职责：用 AppKit 表格在单个 Form 行内承载启动器条目，实现随滚动复用的托管行。
// 分层：UI（NSViewRepresentable 桥接 AppKit 与 SwiftUI）；单元格复用，仅内容随条目变化。
import AppKit
import SwiftUI

/// 在单个 `Form` 行内以表格展示启动器条目，滚动时复用一整屏的托管行。
struct LauncherItemsTable: NSViewRepresentable {
    let entries: [AppEntry]
    let isEnabled: Bool
    let visibility: VisibilityStore
    let aliases: AliasStore
    let hotKeys: HotKeyManager
    /// 行内的本地化文案需要它；托管行不在 Settings 的环境树里，必须显式注入。
    let settings: AppSettings
    /// 已打开的录制器在本视图坐标系中的边界；没有录制时为零。
    @Binding var recorderFrame: CGRect?

    /// 在首行与末行保留 Form 边缘内缩的一小部分。
    static let tableOverhang: CGFloat = 10
    static let searchDividerHeight: CGFloat = 1
    static let rowHeight: CGFloat = 45

    /// 创建表格的 Coordinator（数据源与代理）。
    func makeCoordinator() -> Coordinator { Coordinator() }

    /// 构建承载行的 NSTableView 及其外扩容器。
    func makeNSView(context: Context) -> NSView {
        let table = HostedRowsTableView()
        table.headerView = nil
        table.style = .plain
        table.rowHeight = Self.rowHeight
        table.intercellSpacing = .zero
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .none
        table.focusRingType = .none
        table.refusesFirstResponder = true
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        context.coordinator.table = table
        let container = OverhangingTableView(
            table: table,
            topOverhang: Self.tableOverhang + Self.searchDividerHeight,
            bottomOverhang: Self.tableOverhang)
        context.coordinator.container = container
        return container
    }

    /// 把最新数据交给 Coordinator 刷新可见单元格。
    func updateNSView(_ container: NSView, context: Context) {
        context.coordinator.show(self)
    }

    /// 按行数计算表格高度，并扣除上下外扩与分隔线。
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        let rows = CGFloat(entries.count) * Self.rowHeight
        return CGSize(
            width: proposal.width ?? nsView.frame.width,
            height: rows - 2 * Self.tableOverhang - Self.searchDividerHeight)
    }

    /// 表格的数据源与代理，负责行内容、单元格复用与录制器锚点转发。
    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        fileprivate weak var table: NSTableView?
        fileprivate weak var container: NSView?
        private var list: LauncherItemsTable?
        private var shownIDs: [AppEntry.ID] = []
        private weak var recorderOwner: LauncherItemCellView?

        fileprivate func show(_ list: LauncherItemsTable) {
            self.list = list
            guard let table else { return }
            let ids = list.entries.map(\.id)
            guard ids == shownIDs else {
                shownIDs = ids
                table.reloadData()
                return
            }
            // 行未变：就地刷新可见单元格，使正在聚焦的别名输入框保留编辑器。
            let visible = table.rows(in: table.visibleRect)
            for row in visible.location..<visible.location + visible.length {
                let cell = table.view(atColumn: 0, row: row, makeIfNecessary: false)
                (cell as? LauncherItemCellView)?.show(content(for: row, of: list))
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            list?.entries.count ?? 0
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let list else { return nil }
            let content = content(for: row, of: list)
            let reused = tableView.makeView(withIdentifier: LauncherItemCellView.reuseID, owner: nil)
            let cell = reused as? LauncherItemCellView ?? LauncherItemCellView(content)
            cell.coordinator = self
            cell.show(content)
            return cell
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }

        /// 把焦点移到该单元格下一行的别名输入框，失败时返回 false。
        fileprivate func focusAlias(below cell: LauncherItemCellView) -> Bool {
            guard let table else { return false }
            let row = table.row(for: cell) + 1
            guard row > 0, row < table.numberOfRows else { return false }
            table.scrollRowToVisible(row)
            let next = table.view(atColumn: 0, row: row, makeIfNecessary: true) as? LauncherItemCellView
            return next?.focusAlias() ?? false
        }

        /// 接收单元格上报的录制器位置并对外发布，nil 表示录制结束。
        fileprivate func recorderMoved(to frame: CGRect?, in cell: LauncherItemCellView) {
            if let frame {
                recorderOwner = cell
                publish(frame)
            } else if recorderOwner === cell {
                recorderOwner = nil
                publish(nil)
            }
        }

        /// 仅在变化时把录制器边界写回绑定。
        private func publish(_ frame: CGRect?) {
            guard let list, list.recorderFrame != frame else { return }
            list.recorderFrame = frame
        }

        /// 构造指定行对应的单元格内容。
        private func content(for row: Int, of list: LauncherItemsTable) -> LauncherItemCell {
            LauncherItemCell(
                entry: list.entries[row], showsDivider: row > 0, isEnabled: list.isEnabled,
                visibility: list.visibility, aliases: list.aliases, hotKeys: list.hotKeys,
                settings: list.settings)
        }
    }
}

/// 让表格外扩进 `Form` 行的内边距：AppKit 视图无法用负 padding 实现位移。
private final class OverhangingTableView: NSView {
    private let table: NSTableView
    private let topOverhang: CGFloat
    private let bottomOverhang: CGFloat

    init(table: NSTableView, topOverhang: CGFloat, bottomOverhang: CGFloat) {
        self.table = table
        self.topOverhang = topOverhang
        self.bottomOverhang = bottomOverhang
        super.init(frame: .zero)
        addSubview(table)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        table.frame = NSRect(
            x: bounds.minX, y: bounds.minY - topOverhang,
            width: bounds.width, height: bounds.height + topOverhang + bottomOverhang)
    }
}

/// 把每次点击都交给宿主行；否则表格会吞掉未命中 `NSControl` 的点击。
private final class HostedRowsTableView: NSTableView {
    override func validateProposedFirstResponder(_ responder: NSResponder, for event: NSEvent?) -> Bool {
        true
    }
}

/// 可复用的行：其托管的输入框与复选框得以保留，只有条目内容发生替换。
private final class LauncherItemCellView: NSTableCellView {
    static let reuseID = NSUserInterfaceItemIdentifier("launcherItem")
    weak var coordinator: LauncherItemsTable.Coordinator?
    private let host: NSHostingView<LauncherItemCell>

    init(_ content: LauncherItemCell) {
        host = NSHostingView(rootView: content)
        super.init(frame: .zero)
        identifier = Self.reuseID
        // 表格固定行高；若让托管视图自行决定尺寸会与之冲突。
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.topAnchor.constraint(equalTo: topAnchor),
            host.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(_ content: LauncherItemCell) {
        var content = content
        content.onRecorderFrame = { [weak self] frame in self?.recorderMoved(to: frame) }
        content.onTab = { [weak self] in self?.tabbed() ?? false }
        host.rootView = content
    }

    /// 让本行的别名输入框获得焦点。
    fileprivate func focusAlias() -> Bool {
        guard let field = aliasField else { return false }
        return window?.makeFirstResponder(field) ?? false
    }

    /// 仅在别名正在编辑时处理，使得从聚焦的复选框按 Tab 仍保留默认行为。
    private func tabbed() -> Bool {
        guard let editor = window?.firstResponder as? NSTextView, editor.isFieldEditor,
            let field = editor.delegate as? NSView, field.isDescendant(of: host), let coordinator
        else { return false }
        return coordinator.focusAlias(below: self)
    }

    /// 该行唯一的可编辑输入框就是别名；名称与录制器都是绘制文本。
    private var aliasField: NSTextField? {
        var pending: [NSView] = [host]
        while let view = pending.popLast() {
            if let field = view as? NSTextField, field.isEditable { return field }
            pending.append(contentsOf: view.subviews)
        }
        return nil
    }

    /// 把录制器边界从宿主视图坐标转换到容器坐标后上报。
    private func recorderMoved(to frame: CGRect?) {
        guard let coordinator, let container = coordinator.container else { return }
        coordinator.recorderMoved(to: frame.map { host.convert($0, to: container) }, in: self)
    }
}

/// 单元格托管的内容：行本身，以及 `Form` 行本应提供的分隔细线与环境对象。
private struct LauncherItemCell: View {
    let entry: AppEntry
    let showsDivider: Bool
    let isEnabled: Bool
    let visibility: VisibilityStore
    let aliases: AliasStore
    let hotKeys: HotKeyManager
    let settings: AppSettings
    var onRecorderFrame: @MainActor (CGRect?) -> Void = { _ in }
    var onTab: @MainActor () -> Bool = { false }

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(showsDivider ? 1 : 0)
            LauncherItemRow(entry: entry)
                // 若干行是彼此独立的托管视图；键盘焦点循环不会从一行走到下一行。
                .onKeyPress(.tab, phases: .down) { press in
                    !press.modifiers.contains(.shift) && onTab() ? .handled : .ignored
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .disabled(!isEnabled)
        // 录制器的锚点无法离开该托管视图，因此手动把其边界传出。
        .overlayPreferenceValue(ShortcutRecorderAnchorKey.self) { anchor in
            GeometryReader { proxy in
                Color.clear.onChange(of: anchor.map { proxy[$0] }, initial: true) { _, frame in
                    onRecorderFrame(frame)
                }
            }
        }
        .environment(visibility)
        .environment(aliases)
        .environment(hotKeys)
        .environment(settings)
    }
}
