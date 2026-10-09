// 文件职责：把模型选择集合实现为一个 NSTableView 复选框清单，通过 NSViewRepresentable 嵌入 SwiftUI Form 行，以应对数量庞大的模型目录（如 OpenCode 的 400 个）。
// 分层：UI；仅桥接 AppKit 并回调勾选状态，不持有业务状态。
import AppKit
import SwiftUI

/// 把模型以复选框形式放在同一 Form 行内：Form 会实例化每一行，而 OpenCode 有 400 个模型。
struct AIModelChecklist: NSViewRepresentable {
    /// 一个清单项：模型 id、标题、是否勾选，以及是否为默认模型。
    struct Item: Equatable {
        let id: String
        let title: String
        let isOn: Bool
        /// 默认模型：始终列出，因此它的复选框不可取消。
        let isLocked: Bool
    }

    let items: [Item]
    let onToggle: (String, Bool) -> Void

    /// 分组 Form 行自带的垂直内边距，首尾行已各自承担一次。
    static let rowPadding: CGFloat = 9
    /// 单行高度：复选框自身高度加上下内边距。
    static let rowHeight: CGFloat = 18 + 2 * rowPadding

    /// 创建 NSTableView 的数据源与代理协调器。
    func makeCoordinator() -> Coordinator { Coordinator() }

    /// 创建并配置承载复选框清单的 NSTableView，外层包一层容器用于行内边距对齐。
    func makeNSView(context: Context) -> NSView {
        let table = NSTableView()
        table.headerView = nil
        table.style = .plain
        table.rowHeight = Self.rowHeight
        table.intercellSpacing = .zero
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .none
        table.focusRingType = .none
        table.refusesFirstResponder = true
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("model"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        context.coordinator.table = table
        return ChecklistContainer(table: table, overhang: Self.rowPadding)
    }

    /// 视图更新时把最新数据交给协调器刷新行内容。
    func updateNSView(_ container: NSView, context: Context) {
        context.coordinator.show(self)
    }

    /// 按行数与行高计算清单高度，并扣除首尾行的额外内边距。
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        let rows = CGFloat(items.count) * Self.rowHeight
        return CGSize(width: proposal.width ?? nsView.frame.width, height: rows - 2 * Self.rowPadding)
    }

    /// 负责 NSTableView 的数据源与代理，并在数据变化时增量刷新可见行。
    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        fileprivate weak var table: NSTableView?
        private var list: AIModelChecklist?
        private var shownIDs: [String] = []

        /// 展示最新清单：id 顺序变化时整体重载，否则只刷新可见行。
        fileprivate func show(_ list: AIModelChecklist) {
            self.list = list
            guard let table else { return }
            let ids = list.items.map(\.id)
            guard ids == shownIDs else {
                shownIDs = ids
                table.reloadData()
                return
            }
            let visible = table.rows(in: table.visibleRect)
            for row in visible.location..<visible.location + visible.length {
                let cell = table.view(atColumn: 0, row: row, makeIfNecessary: false)
                (cell as? ChecklistCellView)?.show(list.items[row], showsDivider: row > 0)
            }
        }

        /// 行数等于清单项数量。
        func numberOfRows(in tableView: NSTableView) -> Int {
            list?.items.count ?? 0
        }

        /// 复用或新建复选框单元格，并把对应项的内容填入。
        func tableView(
            _ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int
        ) -> NSView? {
            guard let list else { return nil }
            let reused = tableView.makeView(withIdentifier: ChecklistCellView.reuseID, owner: nil)
            let cell = reused as? ChecklistCellView ?? ChecklistCellView()
            cell.onToggle = { [weak self] id, isOn in self?.list?.onToggle(id, isOn) }
            cell.show(list.items[row], showsDivider: row > 0)
            return cell
        }

        /// 复选框行不参与表格选中。
        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }
    }
}

/// 把表格挂到 Form 行的内边距区域：负内边距无法移动 AppKit 视图，因此用容器放大边界。
private final class ChecklistContainer: NSView {
    private let table: NSTableView
    private let overhang: CGFloat

    /// 用表格与溢出量构造容器，并把表格添加到自身。
    init(table: NSTableView, overhang: CGFloat) {
        self.table = table
        self.overhang = overhang
        super.init(frame: .zero)
        addSubview(table)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// 采用翻转坐标系，使表格内容从顶部开始排列。
    override var isFlipped: Bool { true }

    /// 尺寸变化时把表格按溢出量向外扩展，以抵消 Form 行的内边距。
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        table.frame = bounds.insetBy(dx: 0, dy: -overhang)
    }
}

/// 可复用的行视图：系统复选框、默认模型标记，以及 Form 行会绘制的细分割线。
private final class ChecklistCellView: NSTableCellView {
    static let reuseID = NSUserInterfaceItemIdentifier("modelChecklistRow")
    var onToggle: (String, Bool) -> Void = { _, _ in }
    private let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let defaultTag = NSTextField(labelWithString: "Default")
    private let divider = NSBox()
    private var itemID = ""

    init() {
        super.init(frame: .zero)
        identifier = Self.reuseID
        checkbox.target = self
        checkbox.action = #selector(toggled)
        checkbox.lineBreakMode = .byTruncatingMiddle
        defaultTag.textColor = .secondaryLabelColor
        divider.boxType = .separator
        for view in [checkbox, defaultTag, divider] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            checkbox.leadingAnchor.constraint(equalTo: leadingAnchor),
            checkbox.centerYAnchor.constraint(equalTo: centerYAnchor),
            checkbox.trailingAnchor.constraint(
                lessThanOrEqualTo: defaultTag.leadingAnchor, constant: -Theme.Spacing.lg),
            defaultTag.trailingAnchor.constraint(equalTo: trailingAnchor),
            defaultTag.centerYAnchor.constraint(equalTo: centerYAnchor),
            divider.leadingAnchor.constraint(equalTo: leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor),
            divider.topAnchor.constraint(equalTo: topAnchor)
        ])
        defaultTag.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// 填入一行内容：标题、勾选状态、是否锁定为默认，以及是否显示分割线。
    func show(_ item: AIModelChecklist.Item, showsDivider: Bool) {
        itemID = item.id
        checkbox.title = item.title
        checkbox.state = item.isOn || item.isLocked ? .on : .off
        checkbox.isEnabled = !item.isLocked
        defaultTag.isHidden = !item.isLocked
        divider.isHidden = !showsDivider
    }

    /// 复选框被点击时把新的勾选状态回调出去。
    @objc private func toggled() {
        onToggle(itemID, checkbox.state == .on)
    }
}
