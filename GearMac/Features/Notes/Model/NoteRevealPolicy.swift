// 文件职责：决定哪些行显示原始 Markdown 而不是渲染后的形态，并在编辑后平移该集合。
// 分层：Model；纯逻辑、不依赖 AppKit/SwiftUI。
import Foundation

/// 决定哪些行显示原始 Markdown 而不是渲染后的形态。
enum NoteRevealPolicy {
    /// 显示原始语法的行：选区所在的行，并扩展到完整的围栏块。
    static func revealedLines(
        selection: NSRange, markdown: NoteMarkdown, isFocused: Bool
    ) -> IndexSet {
        guard isFocused, selection.location != NSNotFound else { return IndexSet() }
        var revealed = IndexSet(integersIn: markdown.lineIndexes(intersecting: selection))
        guard let first = revealed.first, let last = revealed.last else { return revealed }
        for block in markdown.fenceBlocks where block.overlaps(first...last) {
            revealed.insert(block.lowerBound)
            revealed.insert(block.upperBound)
        }
        return revealed
    }

    /// 把「已揭示」集合跨编辑平移，使过期的行仍能被找到并重新隐藏。
    static func shifted(
        _ revealed: IndexSet, editedOldLines: Range<Int>, editedNewLines: Range<Int>
    ) -> IndexSet {
        let delta = editedNewLines.count - editedOldLines.count
        var shifted = IndexSet()
        for index in revealed where !editedOldLines.contains(index) {
            shifted.insert(index < editedOldLines.lowerBound ? index : index + delta)
        }
        shifted.insert(integersIn: editedNewLines)
        return shifted
    }
}
