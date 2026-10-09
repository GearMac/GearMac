// 文件职责：管理用户自定义窗口尺寸库，以 JSON 形式存入 UserDefaults，并对记录做校验与清洗。
// 分层：Model；保持纯净（MainActor + @Observable），仅依赖 Foundation，不 import AppKit/SwiftUI。
import Foundation

/// 自定义尺寸库，以 JSON 形式放在 `UserDefaults` 中。属于用户编写的数据，因此坏记录会被清洗。
@MainActor
@Observable
final class CustomWindowSizeStore {
    private static let defaultsKey = "customWindowSizes"

    private let defaults: UserDefaults
    private(set) var sizes: [CustomWindowSize]
    @ObservationIgnored var onChange: (([CustomWindowSize]) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let decoded =
            defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode([CustomWindowSize].self, from: $0) } ?? []
        sizes = Self.sanitized(decoded)
        if sizes != decoded { persist() }
    }

    func size(id: UUID) -> CustomWindowSize? {
        sizes.first { $0.id == id }
    }

    @discardableResult
    func add(
        _ draft: CustomWindowSize
    ) throws(CustomWindowSizeValidationError) -> CustomWindowSize {
        let value = try validated(draft)
        commit(sizes + [value])
        return value
    }

    func update(_ draft: CustomWindowSize) throws(CustomWindowSizeValidationError) {
        guard let index = sizes.firstIndex(where: { $0.id == draft.id }) else { return }
        let value = try validated(draft)
        var updated = sizes
        updated[index] = value
        commit(updated)
    }

    @discardableResult
    func remove(id: UUID) -> CustomWindowSize? {
        guard let index = sizes.firstIndex(where: { $0.id == id }) else { return nil }
        var updated = sizes
        let removed = updated.remove(at: index)
        commit(updated)
        return removed
    }

    /// 导入备份时整体替换尺寸库，清洗而不是拒绝。
    @discardableResult
    func replace(with incoming: [CustomWindowSize]) -> Int {
        let updated = Self.sanitized(incoming)
        commit(updated)
        return updated.count
    }

    private func validated(
        _ draft: CustomWindowSize
    ) throws(CustomWindowSizeValidationError) -> CustomWindowSize {
        let value = draft.sanitized
        guard !value.name.isEmpty else { throw .emptyName }
        guard !value.name.contains("\0") else { throw .invalidCharacter }
        guard
            !sizes.contains(where: {
                $0.id != value.id
                    && $0.name.compare(value.name, options: .caseInsensitive) == .orderedSame
            })
        else { throw .duplicateName }
        return value
    }

    private func commit(_ updated: [CustomWindowSize]) {
        let ordered = updated.sorted(by: CustomWindowSize.precedes)
        guard ordered != sizes else { return }
        sizes = ordered
        persist()
        onChange?(ordered)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(sizes) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    private static func sanitized(_ values: [CustomWindowSize]) -> [CustomWindowSize] {
        var ids = Set<UUID>()
        var names = Set<String>()
        var result: [CustomWindowSize] = []
        for value in values {
            let cleaned = value.sanitized
            // 不本地化，使导入时拒绝的名称与 `validated` 拒绝的完全一致。
            let foldedName = cleaned.name.folding(options: [.caseInsensitive], locale: nil)
            guard !cleaned.name.isEmpty, !cleaned.name.contains("\0"),
                ids.insert(cleaned.id).inserted, names.insert(foldedName).inserted
            else { continue }
            result.append(cleaned)
        }
        return result.sorted(by: CustomWindowSize.precedes)
    }
}
