// 文件职责：承载编辑器 sheet 中一次进行中的布局编辑状态（选择、增删条目、改尺寸锚点偏移）并产出保存结果。
// 分层：Model；保持纯净（MainActor + @Observable），仅依赖 CoreGraphics/Foundation。
import CoreGraphics
import Foundation

/// 一次进行中的布局编辑。由编辑器 sheet 持有，关闭即消失。
@MainActor
@Observable
final class WindowLayoutDraft {
    /// 编辑器步进器允许的范围；模型本身接受 0…1 内的任意比例。
    static let percentRange: ClosedRange<Int> = 5...100
    static let offsetRange: ClosedRange<Int> = -4000...4000

    /// 新布局为 nil；保留它使保存编辑时能守住 UUID 及其上所有引用。
    let existingID: UUID?
    let isCapture: Bool
    var name: String
    var iconSymbol: String?
    var usesPreferredGap: Bool
    private(set) var entries: [WindowLayoutEntry]
    private var frontmostEntryID: UUID?
    /// 用身份而非下标：删除条目不得让某个字段的绑定悬空。
    private(set) var selectedEntryID: UUID?
    private(set) var selectedDisplayUUID: String?

    init(layout: WindowLayout?, isCapture: Bool = false, displays: [WindowLayoutDisplay]) {
        existingID = layout?.id
        self.isCapture = isCapture
        name = layout?.name ?? ""
        iconSymbol = layout?.iconSymbol
        usesPreferredGap = layout?.usesPreferredGap ?? true
        entries = layout?.entries ?? []
        frontmostEntryID = layout?.frontmostEntryID
        selectedEntryID = entries.first?.id
        selectedDisplayUUID = entries.first?.display.uuid ?? displays.first?.uuid
    }

    var symbol: String { iconSymbol ?? WindowLayout.sfSymbol }
    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !entries.isEmpty
    }

    var selectedEntry: WindowLayoutEntry? {
        entries.first { $0.id == selectedEntryID }
    }

    /// 标记第二个条目会移走标记，因此布局从不同时标两个。
    var isSelectedEntryFrontmost: Bool {
        get { selectedEntryID != nil && frontmostEntryID == selectedEntryID }
        set {
            guard let id = selectedEntryID else { return }
            if newValue {
                frontmostEntryID = id
            } else if frontmostEntryID == id {
                frontmostEntryID = nil
            }
        }
    }

    func entries(onDisplay uuid: String) -> [WindowLayoutEntry] {
        entries.filter { $0.display.uuid == uuid }
    }

    /// sheet 必须提供标签页的每块显示器：已连接的，加上任何条目命名的。
    func tabs(connected: [WindowLayoutDisplay]) -> [WindowLayoutDisplay] {
        var seen = Set(connected.map(\.uuid))
        var result = connected
        for entry in entries where seen.insert(entry.display.uuid).inserted {
            result.append(entry.display)
        }
        return result
    }

    // MARK: - Selection

    /// 一个选择的两种视图，使标签页与条目选择器永不会不一致。
    func select(entryID: UUID) {
        guard let entry = entries.first(where: { $0.id == entryID }) else { return }
        selectedEntryID = entryID
        selectedDisplayUUID = entry.display.uuid
    }

    func select(displayUUID: String) {
        selectedDisplayUUID = displayUUID
        if selectedEntry?.display.uuid != displayUUID {
            selectedEntryID = entries(onDisplay: displayUUID).first?.id
        }
    }

    // MARK: - Editing

    func addEntry(bundleID: String, on display: WindowLayoutDisplay) {
        let entry = WindowLayoutEntry(bundleID: bundleID, display: display)
        entries.append(entry)
        select(entryID: entry.id)
    }

    func removeSelectedEntry() {
        guard let id = selectedEntryID else { return }
        entries.removeAll { $0.id == id }
        if frontmostEntryID == id { frontmostEntryID = nil }
        selectedEntryID =
            selectedDisplayUUID.flatMap { entries(onDisplay: $0).first?.id }
            ?? entries.first?.id
    }

    func setArgument(_ argument: String?) {
        update { $0.argument = argument?.isEmpty == true ? nil : argument }
    }

    func setDisplay(_ display: WindowLayoutDisplay) {
        update { $0.display = display }
        selectedDisplayUUID = display.uuid
    }

    func setAnchor(_ anchor: WindowLayoutAnchor) {
        update { $0.anchor = anchor }
    }

    func setWidthPercent(_ percent: Int) {
        update { $0.widthFraction = Self.fraction(percent) }
    }

    func setHeightPercent(_ percent: Int) {
        update { $0.heightFraction = Self.fraction(percent) }
    }

    func setOffsetX(_ points: Int) {
        update { $0.offset.x = CGFloat(points.clamped(to: Self.offsetRange)) }
    }

    func setOffsetY(_ points: Int) {
        update { $0.offset.y = CGFloat(points.clamped(to: Self.offsetRange)) }
    }

    // MARK: - Output

    /// 预览绘制的内容——未校验，因此未命名的草稿也能显示它的窗口。
    var previewLayout: WindowLayout {
        WindowLayout(
            id: existingID ?? UUID(), name: name, iconSymbol: iconSymbol,
            usesPreferredGap: usesPreferredGap, entries: entries,
            frontmostEntryID: frontmostEntryID)
    }

    /// Save 持久化的内容；sheet 自己从不组装记录。
    func layout() -> WindowLayout {
        var value = previewLayout
        value.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return value
    }

    // MARK: - Primitives

    static func percent(_ fraction: CGFloat) -> Int {
        guard fraction.isFinite else { return 100 }
        return Int((fraction * 100).rounded()).clamped(to: percentRange)
    }

    private static func fraction(_ percent: Int) -> CGFloat {
        CGFloat(percent.clamped(to: percentRange)) / 100
    }

    private func update(_ change: (inout WindowLayoutEntry) -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == selectedEntryID }) else { return }
        change(&entries[index])
    }
}

extension Int {
    /// 饱和式夹取，使输入的数字被修正而不是拒绝。
    fileprivate func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
