// 文件职责：实现词级别文本差异算法，供改写等动作展示改前改后对比。
// 分层：Model；算法自包含、无副作用，不依赖 AppKit/SwiftUI。
import Foundation

/// 词级别的 diff，使改写能直接展示改了什么，而不需要读者自行找差异。
enum TextDiffEngine: Sendable {
    /// 差异结果的片段：相同 / 新增 / 删除。
    enum Chunk: Equatable, Sendable {
        case equal(String)
        case inserted(String)
        case deleted(String)
    }

    /// 即使做了位压缩，回溯仍是二次开销；累计得分必须仍能放进 `UInt16`。
    static let maxTokens = 4_000

    /// 计算两段文本的词级差异，返回按顺序排列的片段。
    static func diff(original: String, modified: String) -> [Chunk] {
        if original == modified { return original.isEmpty ? [] : [.equal(original)] }
        if original.isEmpty { return [.inserted(modified)] }
        if modified.isEmpty { return [.deleted(original)] }

        let old = tokenize(original)
        let new = tokenize(modified)
        guard old.count <= maxTokens, new.count <= maxTokens else {
            return [.deleted(original), .inserted(modified)]
        }

        let traceback = Traceback(old, new)
        var reversed: [Chunk] = []
        var i = old.count
        var j = new.count
        while i > 0 || j > 0 {
            if i > 0, j > 0, old[i - 1] == new[j - 1] {
                reversed.append(.equal(old[i - 1]))
                i -= 1
                j -= 1
            } else if j > 0, i == 0 || traceback.inserts(row: i - 1, column: j - 1) {
                reversed.append(.inserted(new[j - 1]))
                j -= 1
            } else {
                reversed.append(.deleted(old[i - 1]))
                i -= 1
            }
        }
        return coalesce(reversed.reversed())
    }

    /// 切分为单词及其间的片段，使变更落在边界上而不是字母中间。
    private static func tokenize(_ string: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inWord = false
        for character in string {
            let isWordCharacter = character.isLetter || character.isNumber
            if isWordCharacter == inWord, !current.isEmpty {
                current.append(character)
            } else {
                if !current.isEmpty { tokens.append(current) }
                current = String(character)
                inWord = isWordCharacter
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    /// 保存回溯所需的方向位图（LCS 方向的位压缩）。
    private struct Traceback {
        let columns: Int
        let insertions: [UInt8]

        init(_ old: [String], _ new: [String]) {
            // 计算 LCS 长度得分，并用位图记录每个格子的方向。
            columns = new.count
            var scores = [UInt16](repeating: 0, count: new.count + 1)
            var bits = [UInt8](repeating: 0, count: (old.count * new.count + 7) / 8)
            for i in old.indices {
                var diagonal: UInt16 = 0
                for j in new.indices {
                    let above = scores[j + 1]
                    if old[i] == new[j] {
                        scores[j + 1] = diagonal + 1
                    } else if scores[j] >= above {
                        scores[j + 1] = scores[j]
                        let index = i * new.count + j
                        bits[index >> 3] |= UInt8(1) << (index & 7)
                    }
                    diagonal = above
                }
            }
            insertions = bits
        }

        // 回溯时会先比较相等，所以只需一个位区分“插入还是删除”。
        func inserts(row: Int, column: Int) -> Bool {
            let index = row * columns + column
            return insertions[index >> 3] & (UInt8(1) << (index & 7)) != 0
        }
    }

    /// 相邻同类型片段合并，使读者看到的是一个被改的短语，而不是五个词。
    private static func coalesce(_ chunks: [Chunk]) -> [Chunk] {
        chunks.reduce(into: []) { result, chunk in
            switch (result.last, chunk) {
            case (.equal(let a), .equal(let b)): result[result.count - 1] = .equal(a + b)
            case (.inserted(let a), .inserted(let b)): result[result.count - 1] = .inserted(a + b)
            case (.deleted(let a), .deleted(let b)): result[result.count - 1] = .deleted(a + b)
            default: result.append(chunk)
            }
        }
    }
}
