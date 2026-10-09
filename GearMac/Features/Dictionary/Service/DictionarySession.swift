// 文件职责：驱动词典界面的查询会话，对输入做防抖并在主 actor 之外求解词条。
// 分层：Service；只维护查询状态与任务取消，不直接触碰 UI。
import Foundation

/// 词典界面的查询：同时只进行一个词条，结果在主 actor 之外得出。
@MainActor
@Observable
final class DictionarySession {
    /// 一次已完成的查询：查询词与对应词条。
    struct Lookup: Equatable {
        let term: String
        /// 当没有已启用辞典认识该词条时为 nil。
        let entry: DictionaryEntry?
    }

    /// 最近一次已完成的查询；下一个词条解析期间它保持不变，因此输入时界面不会闪空。
    private(set) var lookup: Lookup?
    @ObservationIgnored private var term = ""
    @ObservationIgnored private var task: Task<Void, Never>?

    /// 将连绩的按键归并为最终确定词语的那一次查询。
    private static let debounce = Duration.milliseconds(90)

    /// 对查询做去空白与防抖；空查询直接清空结果，相同词不重复查询。
    func lookUp(_ query: String) {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term != self.term else { return }
        self.term = term
        task?.cancel()
        guard !term.isEmpty else {
            lookup = nil
            return
        }
        task = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            let entry = await Task.detached(priority: .userInitiated) {
                DictionaryService.entry(for: term)
            }.value
            guard !Task.isCancelled else { return }
            self?.lookup = Lookup(term: term, entry: entry)
        }
    }

    /// 取消进行中的查询并清空查询词与结果。
    func reset() {
        task?.cancel()
        task = nil
        term = ""
        lookup = nil
    }
}
