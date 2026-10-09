// 文件职责：Qwen 识别器使用的 BPE 分词器，负责 prompt 编码与生成 token 的解码。
// 分层：Helper/纯计算；只依赖 vocab.json/merges.txt 数据，不做网络与 UI。
import Foundation

/// 字节级 BPE 分词器：加载词表与合并规则，支持编码 prompt 与解码生成结果。
final class DictationTokenizer {
    /// 合并规则中的相邻 token 对。
    private struct Pair: Hashable { let left: String; let right: String }
    private let pieces: [Int: String]
    private let characterBytes: [Unicode.Scalar: UInt8]
    private let prompts: [String: [Int]]

    /// 解析词表、合并规则与预置 prompt，并预计算每个 prompt 的 token 序列。
    init(vocabulary data: Data, merges: String, prompts: [String]) throws {
        let vocabulary = try JSONDecoder().decode([String: Int].self, from: data)
        guard Set(vocabulary.values).count == vocabulary.count else { throw CocoaError(.coderReadCorrupt) }
        pieces = Dictionary(uniqueKeysWithValues: vocabulary.map { ($0.value, $0.key) })
        var ranks = [Pair: Int]()
        for line in merges.split(separator: "\n") where !line.hasPrefix("#") {
            let parts = line.split(separator: " ")
            guard parts.count == 2 else { throw CocoaError(.coderReadCorrupt) }
            ranks[Pair(left: String(parts[0]), right: String(parts[1]))] = ranks.count
        }
        var extra = 256
        var characters = [String]()
        var bytes = [Unicode.Scalar: UInt8]()
        for byte in 0...255 {
            let literal =
                (33...126).contains(byte) || (161...172).contains(byte) || (174...255).contains(byte)
            let scalar = Unicode.Scalar(literal ? byte : extra)!
            if !literal { extra += 1 }
            characters.append(String(scalar))
            bytes[scalar] = UInt8(byte)
        }
        characterBytes = bytes
        let pattern = try NSRegularExpression(
            pattern:
                #"(?i:'s|'t|'re|'ve|'m|'ll|'d)|[^\r\n\p{L}\p{N}]?\p{L}+|\p{N}{1,3}|"#
                + #" ?[^\s\p{L}\p{N}]+[\r\n]*|\s*[\r\n]+|\s+(?!\S)|\s+"#)
        self.prompts = Dictionary(
            uniqueKeysWithValues: try Set(prompts).map { text in
                (
                    text,
                    try Self.encode(
                        text, vocabulary: vocabulary, ranks: ranks,
                        byteCharacters: characters, pattern: pattern)
                )
            })
    }

    /// 返回预置 prompt 对应的 token 序列；未预置的 prompt 视为非法。
    func tokens(for prompt: String) throws -> [Int] {
        guard let tokens = prompts[prompt] else { throw CocoaError(.coderInvalidValue) }
        return tokens
    }

    /// 按 GPT-2 正则切分后用 BPE 规则合并，得到文本的 token 序列。
    private static func encode(
        _ text: String, vocabulary: [String: Int], ranks: [Pair: Int],
        byteCharacters: [String], pattern: NSRegularExpression
    ) throws -> [Int] {
        var tokens = [Int]()
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { throw CocoaError(.coderInvalidValue) }
            var parts = text[range].utf8.map { byteCharacters[Int($0)] }
            while parts.count > 1 {
                let candidate = (0..<(parts.count - 1)).compactMap { index -> (Int, Int)? in
                    guard let rank = ranks[Pair(left: parts[index], right: parts[index + 1])] else {
                        return nil
                    }
                    return (index, rank)
                }.min { $0.1 < $1.1 }
                guard let (index, _) = candidate else { break }
                parts[index] += parts.remove(at: index + 1)
            }
            for part in parts {
                guard let token = vocabulary[part] else { throw CocoaError(.coderInvalidValue) }
                tokens.append(token)
            }
        }
        return tokens
    }

    /// 把 token 序列还原为 UTF-8 文本（逐字节拼接，无效字节序报错）。
    func decode(_ tokens: [Int]) throws -> String {
        let bytes = tokens.flatMap { token -> [UInt8] in
            guard let piece = pieces[token] else { return [] }
            return piece.unicodeScalars.compactMap { characterBytes[$0] }
        }
        guard let text = String(bytes: bytes, encoding: .utf8) else { throw CocoaError(.coderReadCorrupt) }
        return text
    }
}
