// 文件职责：定义快捷动作读取/处理选区时可以出现的失败类型及其用户文案。
// 分层：Model；纯错误枚举，不依赖 AppKit/SwiftUI。
import Foundation

/// 每种失败对应一个独立原因：笼统的“什么都没选”会让把已选中的内容当成没选。
enum QuickActionFailure: LocalizedError, Equatable {
    case needsAccessibility
    case noTarget
    /// 目标应用有应答，但没有暴露获得焦点的文本元素 —— Chromium 在建树前就是这样。
    case unreadableApp(String)
    case noSelection
    case tooLong

    var errorDescription: String? {
        switch self {
        case .needsAccessibility:
            return "GearMac needs the Accessibility permission to read the selected text."
        case .noTarget:
            return "Select text in another app first."
        case .unreadableApp(let name):
            return "\(name) doesn't share its text with GearMac."
        case .noSelection:
            return "Select some text first."
        case .tooLong:
            return "That selection is too long to work on."
        }
    }

    /// 按界面语言解析的面向用户错误描述。
    func message(_ language: AppLanguage) -> String {
        switch self {
        case .needsAccessibility:
            return L10n.string(QuickActionsKey.failureNeedsAccessibility, language: language)
        case .noTarget:
            return L10n.string(QuickActionsKey.failureNoTarget, language: language)
        case .unreadableApp(let name):
            return String(
                format: L10n.string(QuickActionsKey.failureUnreadableApp, language: language), name)
        case .noSelection:
            return L10n.string(QuickActionsKey.failureNoSelection, language: language)
        case .tooLong:
            return L10n.string(QuickActionsKey.failureTooLong, language: language)
        }
    }

    /// 唯一有地方可去（系统设置）的失败，也是唯一值得弹对话框的一种。
    var opensAccessibilitySettings: Bool { self == .needsAccessibility }
}
