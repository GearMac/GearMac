// 文件职责：管理窗口布局库（增删改查、复制、导入替换），以 JSON 存入 UserDefaults 并校验清洗。
// 分层：Model；保持纯净（MainActor + @Observable），仅依赖 Foundation，不 import AppKit/SwiftUI。
import Foundation

/// 布局库。属于用户编写的数据，因此坏记录会被清洗而非丢弃。
@MainActor
@Observable
final class WindowLayoutStore {
    private static let defaultsKey = "windowLayouts"

    private let defaults: UserDefaults
    private(set) var layouts: [WindowLayout]
    @ObservationIgnored var onChange: (([WindowLayout]) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let decoded =
            defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode([WindowLayout].self, from: $0) } ?? []
        layouts = Self.sanitized(decoded)
        if layouts != decoded { persist() }
    }

    func layout(id: UUID) -> WindowLayout? {
        layouts.first { $0.id == id }
    }

    func layout(entryID: String) -> WindowLayout? {
        WindowLayout.id(fromEntryID: entryID).flatMap(layout)
    }

    // 接收整个 draft，这样新增字段不会牵动每个调用点。
    @discardableResult
    func add(_ draft: WindowLayout) throws(WindowLayoutValidationError) -> WindowLayout {
        let value = try validated(draft)
        commit(layouts + [value])
        return value
    }

    func update(_ draft: WindowLayout) throws(WindowLayoutValidationError) {
        guard let index = layouts.firstIndex(where: { $0.id == draft.id }) else { return }
        let value = try validated(draft)
        var updated = layouts
        updated[index] = value
        commit(updated)
    }

    /// 副本全程使用新身份，因此不会继承原件的快捷键。
    @discardableResult
    func duplicate(id: UUID) throws(WindowLayoutValidationError) -> WindowLayout? {
        guard let original = layout(id: id) else { return nil }
        let entries = original.entries.map(\.copy)
        // 副本使用新 ID，因此最前标记按位置跟随其对应条目。
        let frontmost = original.entries.firstIndex { $0.id == original.frontmostEntryID }
        let copy = WindowLayout(
            name: Self.uniqueName(from: original.name, among: layouts),
            iconSymbol: original.iconSymbol, usesPreferredGap: original.usesPreferredGap,
            entries: entries, frontmostEntryID: frontmost.map { entries[$0].id })
        return try add(copy)
    }

    @discardableResult
    func remove(id: UUID) -> WindowLayout? {
        guard let index = layouts.firstIndex(where: { $0.id == id }) else { return nil }
        var updated = layouts
        let removed = updated.remove(at: index)
        commit(updated)
        return removed
    }

    /// 导入备份时整体替换布局库，清洗而不是拒绝。
    @discardableResult
    func replace(with incoming: [WindowLayout]) -> Int {
        let updated = Self.sanitized(incoming)
        commit(updated)
        return updated.count
    }

    private func validated(
        _ draft: WindowLayout
    ) throws(WindowLayoutValidationError) -> WindowLayout {
        var value = draft
        value.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.iconSymbol = draft.iconSymbol?.trimmingCharacters(in: .whitespacesAndNewlines)
        value.sanitizeEntries()
        guard !value.name.isEmpty else { throw .emptyName }
        guard !value.name.contains("\0") else { throw .invalidCharacter }
        guard !value.entries.isEmpty else { throw .noEntries }
        guard
            !layouts.contains(where: {
                $0.id != value.id
                    && $0.name.compare(value.name, options: .caseInsensitive) == .orderedSame
            })
        else { throw .duplicateName }
        return value
    }

    private func commit(_ updated: [WindowLayout]) {
        let ordered = updated.sorted(by: WindowLayout.precedes)
        guard ordered != layouts else { return }
        layouts = ordered
        persist()
        onChange?(ordered)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(layouts) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    /// “Office” → “Office Copy” → “Office Copy 2”，使复制永远不会卡在校验上。
    private static func uniqueName(from name: String, among existing: [WindowLayout]) -> String {
        let taken = Set(existing.map { $0.name.lowercased() })
        let base = name + " Copy"
        guard taken.contains(base.lowercased()) else { return base }
        var index = 2
        while taken.contains("\(base) \(index)".lowercased()) { index += 1 }
        return "\(base) \(index)"
    }

    private static func sanitized(_ values: [WindowLayout]) -> [WindowLayout] {
        var ids = Set<UUID>()
        var names = Set<String>()
        var result: [WindowLayout] = []
        for value in values {
            // 复制并清洗而不是重建，使新增字段绝不会在导入时被丢弃。
            var cleaned = value
            cleaned.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.iconSymbol = value.iconSymbol?.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.sanitizeEntries()
            let foldedName = cleaned.name.folding(options: [.caseInsensitive], locale: .current)
            guard !cleaned.name.isEmpty, !cleaned.name.contains("\0"), !cleaned.entries.isEmpty,
                ids.insert(cleaned.id).inserted, names.insert(foldedName).inserted
            else { continue }
            result.append(cleaned)
        }
        return result.sorted(by: WindowLayout.precedes)
    }
}
