// 文件职责：端侧 Apple Intelligence 路由的状态、标识与窗口预算，以及把完整快照流转换为增量文本的工具。
// 分层：Model；只依赖 Foundation，不得 import AppKit/SwiftUI。
import Foundation

/// 与 FoundationModels 的枚举保持对应；真实实现放在 `Service/`，以便本文件只依赖 Foundation。
enum AppleIntelligenceStatus: Equatable, Sendable {
    case available
    case deviceNotEligible
    case notEnabled
    case modelNotReady
    case requiresNewerSystem

    /// 模型当前是否可用。
    var isAvailable: Bool { self == .available }

    /// 模型可运行时为 `nil`，因此调用方可以直接以它非空作为唯一的失败条件。
    var message: String? {
        switch self {
        case .available:
            return nil
        case .deviceNotEligible:
            return "This Mac does not support Apple Intelligence."
        case .notEnabled:
            return "Turn on Apple Intelligence in System Settings to chat on device."
        case .modelNotReady:
            return "Apple Intelligence is still downloading its model. Try again shortly."
        case .requiresNewerSystem:
            return "On-device chat needs macOS 26. Use another AI route, or upgrade your Mac."
        }
    }
}

/// 端侧内容过滤强度的应用内表示：与 FoundationModels 的同名选项一一对应。
/// 独立定义的原因：工厂签名不得暴露 26-only 类型，否则所有调用方都被迫引入可用性检查。
enum AppleIntelligenceGuardrails: Sendable, Equatable {
    case `default`
    case permissiveContentTransformations
}

/// 端侧 Apple Intelligence 路由的固定标识与窗口预算。
enum AppleIntelligence {
    /// 这个 id 由我们自己定义而非取自厂商：该路由没有可借用的远端模型名。
    static let modelID = "apple-intelligence"
    static let title = "Apple Intelligence"

    /// 端侧窗口同时容纳提示词与回复，因此两者需要互相留出空间。
    static let contextBudget = 6_000
    static let maxOutputTokens = 1_024
}

/// FoundationModels 每次上报的是到目前为止的完整答案；其他传输层都是增量。
struct AppleIntelligenceDelta {
    private var emitted = ""

    /// 当模型改写了已写内容时直接返回整个快照，因为不存在可丢弃的公共前缀。
    mutating func delta(from snapshot: String) -> String {
        defer { emitted = snapshot }
        guard snapshot.hasPrefix(emitted) else { return snapshot }
        return String(snapshot.dropFirst(emitted.count))
    }
}
