// 文件职责：定义一次 Markdown 编辑计划（替换范围、替换文本与替换后的选区）。
// 分层：Model；纯值类型、`Sendable`，不依赖 AppKit/SwiftUI。
import Foundation

/// 一次替换以及替换后选区的落点，均以源文本坐标表示。
struct NoteEditPlan: Sendable, Equatable {
    let range: NSRange
    let replacement: String
    /// 以替换后的源文本坐标表示。
    let selection: NSRange
}
