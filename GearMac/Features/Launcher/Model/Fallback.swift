// 文件职责：定义启动器兜底项（内置目标与 quicklink）及其稳定 id、打开动词、排序与区块标题。
// 分层：Model；不得 import AppKit/SwiftUI，仅依赖 Foundation。
import Foundation

/// 启动器兜底项：输入的查询即它的输入，因此无论查询内容如何都会被提供。
enum Fallback: Hashable, Sendable {
    /// 内置目标项，按全新安装时的展示顺序排列。
    enum Builtin: String, CaseIterable, Sendable {
        case quickAI
        case searchFiles
        case runShellCommand
        case define

        /// 名称与图标的来源命令，使兜底行读起来与它实际执行的命令一致。
        var command: CommandID {
            switch self {
            case .quickAI: return .quickAI
            case .searchFiles: return .searchFiles
            case .runShellCommand: return .runShellCommand
            case .define: return .define
            }
        }
    }

    case builtin(Builtin)
    case quicklink(UUID)

    /// 该行的 `AppEntry` id，使已存储的顺序在改名与重装后仍然有效。
    var id: String {
        switch self {
        case .builtin(let builtin): return builtin.command.rawValue
        case .quicklink(let id): return Quicklink.entryIDPrefix + id.uuidString.lowercased()
        }
    }

    /// 由 id 还原兜底项；既不是已知内置命令也不是合法 quicklink 时返回 nil。
    init?(id: String) {
        if let command = CommandID(rawValue: id),
            let builtin = Builtin.allCases.first(where: { $0.command == command })
        {
            self = .builtin(builtin)
        } else if let quicklink = Quicklink.id(fromEntryID: id) {
            self = .quicklink(quicklink)
        } else {
            return nil
        }
    }

    /// 底部胶囊按钮的动词：用目标项自己的措辞描述 ↵ 会做什么。
    var openVerb: String {
        switch self {
        case .builtin(.quickAI): return "Ask Quick AI"
        case .builtin(.searchFiles): return "Search Files"
        case .builtin(.runShellCommand): return "Run Shell Command"
        case .builtin(.define): return "Define Word"
        case .quicklink: return "Open Quicklink"
        }
    }

    /// 先按已存顺序，再排列从未见过的项——今天新增的 quicklink 会排在最后。
    static func ordered(_ available: [Fallback], by storedIDs: [String]) -> [Fallback] {
        var remaining = Dictionary(available.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let known = storedIDs.compactMap { remaining.removeValue(forKey: $0) }
        return known + available.filter { remaining[$0.id] != nil }
    }

    /// 区块标题。过长的查询会在中间省略，从而保证结尾的 “with…” 始终可见。
    static func sectionTitle(query: String, limit: Int = 72) -> String {
        guard query.count > limit else { return "Use “\(query)” with…" }
        return "Use “\(query.prefix(limit / 2))…\(query.suffix(limit - limit / 2 - 1))” with…"
    }
}
