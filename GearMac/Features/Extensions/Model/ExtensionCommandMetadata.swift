// 文件职责：记录 `updateCommandMetadata` 为单个命令写入的元数据，以及调度器维护的运行簿记（最近运行、失败计数、菜单栏开关等）。
// 分层：Model；保持纯净、可编解码，不 import AppKit/SwiftUI。
import Foundation

/// `updateCommandMetadata` 为单个命令写入的内容，外加调度器对其的簿记。
struct ExtensionCommandMetadata: Codable, Sendable, Equatable {
    /// 由 `updateCommandMetadata` 设置，用 `null` 清除；为 nil 时回退到 manifest 中的 subtitle。
    var subtitle: String?
    /// 默认关闭，直到首次手动运行或 Settings 中的开关。
    var backgroundEnabled = false
    /// 最近一次运行的时间。
    var lastRun: Date?
    /// 最近一次的运行错误信息。
    var lastError: String?
    /// 连续失败次数，用于退避等策略。
    var consecutiveFailures = 0
    /// 默认关闭，直到命令运行过一次；之后的调度从共享的 lastRun 起算。
    var menuBarEnabled = false
    /// 最近一次稳定下来的渲染结果，使菜单栏项无需重跑扩展即可恢复。
    var menuBarSnapshot: ExtensionMenuBarSnapshot?

    /// 构造一条全部取默认值的空记录。
    init() {}

    /// 每个键独立解码，因此新增字段不会连带弄挂所有命令的记录。
    init(from decoder: Decoder) throws {
        let record = try decoder.container(keyedBy: CodingKeys.self)
        subtitle = try record.decodeIfPresent(String.self, forKey: .subtitle)
        backgroundEnabled = try record.decodeIfPresent(Bool.self, forKey: .backgroundEnabled) ?? false
        lastRun = try record.decodeIfPresent(Date.self, forKey: .lastRun)
        lastError = try record.decodeIfPresent(String.self, forKey: .lastError)
        consecutiveFailures = try record.decodeIfPresent(Int.self, forKey: .consecutiveFailures) ?? 0
        menuBarEnabled = try record.decodeIfPresent(Bool.self, forKey: .menuBarEnabled) ?? false
        menuBarSnapshot = try record.decodeIfPresent(
            ExtensionMenuBarSnapshot.self, forKey: .menuBarSnapshot)
    }
}
