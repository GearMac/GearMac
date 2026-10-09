// 文件职责：单次回复允许的工具调用轮数上限选项。
// 分层：Model；纯枚举映射，不得 import AppKit/SwiftUI。
import Foundation

/// 单次回复在被视为卡死之前，最多可以进行多少轮工具调用。
enum AIToolRounds: Int, CaseIterable, Identifiable, Sendable {
    case ten = 10
    case twentyFive = 25
    case fifty = 50
    case hundred = 100
    case unlimited = -1

    var id: Int { rawValue }

    /// 设置界面里的选项名称。
    func title(_ language: AppLanguage) -> String {
        guard let limit else { return L10n.string(AIKey.toolRoundsUnlimited, language: language) }
        return "\(limit)"
    }

    /// `nil` 表示不设上限：回复会一直运行，直到模型不再请求或用户按下停止。
    var limit: Int? { self == .unlimited ? nil : rawValue }
}
