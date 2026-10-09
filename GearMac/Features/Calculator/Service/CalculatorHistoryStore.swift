// 文件职责：把用户复制过的历史计算记录持久化到 Application Support 下的 JSON 文件，并提供记录、删除、清空、整体替换与搜索能力。
// 分层：Service；@MainActor 隔离，历史条数上限 200，写入均为原子写。
import Foundation

/// 一条历史计算记录，在用户复制答案时写入。
struct CalcHistoryEntry: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let expression: String
    let result: String
    let createdAt: Date

    /// 复制到剪贴板时使用的文本，去掉结果中的千位分隔逗号。
    var copyText: String { result.replacingOccurrences(of: ",", with: "") }
}

/// 有容量上限的 JSON 文件存储，与 `ClipboardStore` 放在同一目录，以便 `brew uninstall --zap` 一并清理。
@MainActor
@Observable
final class CalculatorHistoryStore {
    private static let cap = 200

    private let fileURL: URL

    private(set) var entries: [CalcHistoryEntry]  // 最新的在最前

    /// 搜索结果缓存的键：查询串加上数据版本号。
    private struct SearchKey: Equatable {
        let query: String
        let revision: Int
    }

    /// 重复渲染（方向键导航）复用上一次的过滤结果，而不是重新扫描每条记录。
    @ObservationIgnored private var searchMemo = Memo<SearchKey, [CalcHistoryEntry]>()
    /// 每次已持久化的变更都会自增，使上面的键能唯一标识它过滤时的那批记录。
    private var revision = 0

    init() {
        fileURL = AppPaths.applicationSupport().appendingPathComponent("calculator-history.json")

        if let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode([CalcHistoryEntry].self, from: data)
        {
            entries = decoded
        } else {
            entries = []
        }
    }

    /// 记录一次计算；若与最新一条完全相同则不重复入栈。
    func record(expression: String, result: String) {
        // 重复复制同一个答案（连按两次 Enter，或从历史中再复制）不应堆叠出重复项。
        if let latest = entries.first, latest.expression == expression, latest.result == result {
            return
        }
        entries.insert(
            CalcHistoryEntry(id: UUID(), expression: expression, result: result, createdAt: Date()),
            at: 0)
        if entries.count > Self.cap { entries.removeLast(entries.count - Self.cap) }
        persist()
    }

    /// 按 id 删除单条历史记录。
    func remove(_ entry: CalcHistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        persist()
    }

    /// 清空全部历史记录。
    func clearAll() {
        entries = []
        persist()
    }

    /// 用备份整体替换历史记录，按时间倒序排列并保持同样的容量上限。
    func replace(_ imported: [CalcHistoryEntry]) {
        entries = Array(imported.sorted { $0.createdAt > $1.createdAt }.prefix(Self.cap))
        persist()
    }

    /// 对每条计算的表达式与结果做不区分大小写的子串匹配。
    func search(_ query: String) -> [CalcHistoryEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return entries }
        return searchMemo.value(for: SearchKey(query: q, revision: revision)) {
            entries.filter {
                $0.expression.localizedCaseInsensitiveContains(q)
                    || $0.result.localizedCaseInsensitiveContains(q)
                    || $0.copyText.localizedCaseInsensitiveContains(q)
            }
        }
    }

    /// 递增版本号并把当前记录原子写入磁盘。
    private func persist() {
        revision &+= 1
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
