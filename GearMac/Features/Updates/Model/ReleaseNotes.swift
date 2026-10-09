// 文件职责：把发布说明正文整理为窗口可直接渲染的块结构，并按标记截去安装说明。
// 分层：Model/解析（纯函数）；不做网络请求，也不依赖 SwiftUI。
import Foundation

/// 窗口所读取的发布说明正文：CI 实际产出的那几种块形态。
enum ReleaseNotes {
    /// CI 会在此标记之下写安装说明供下载页使用；窗口会跳过这部分。
    static let installMarker = "<!-- gearmac:install -->"

    /// 在标记出现之前发布的正文不含该标记，会原样返回。
    static func summary(of body: String) -> String {
        let head = body.range(of: installMarker).map { String(body[..<$0.lowerBound]) } ?? body
        return head.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 发布说明的一个内容块：标题、列表项或段落。
    enum Block: Hashable, Sendable {
        case heading(level: Int, text: String)
        case bullet(String)
        case paragraph(String)
    }

    /// 针对 GitHub 发布说明产物的逐行扫描器，而非通用 Markdown 解析器。
    static func blocks(from summary: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []

        func flush() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(linkified(paragraph.joined(separator: "\n"))))
            paragraph.removeAll()
        }

        for raw in summary.replacingOccurrences(of: "\r\n", with: "\n").split(
            separator: "\n", omittingEmptySubsequences: false)
        {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flush()
            } else if let heading = heading(in: line) {
                flush()
                blocks.append(heading)
            } else if let bullet = bullet(in: line) {
                flush()
                blocks.append(.bullet(linkified(bullet)))
            } else {
                paragraph.append(line)
            }
        }
        flush()
        return blocks
    }

    /// 识别 ATX 标题并返回其级别与文本。
    private static func heading(in line: String) -> Block? {
        let hashes = line.prefix(while: { $0 == "#" })
        guard (1...6).contains(hashes.count), line.dropFirst(hashes.count).first == " " else { return nil }
        // Markdown 允许标题以自身的一串 # 收尾，因此两端都要裁剪。
        let text = line.dropFirst(hashes.count)
            .trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        return .heading(level: hashes.count, text: text)
    }

    /// GitHub 在网页上会自动链接 @ 提及；这里必须显式写成 Markdown 链接。
    private static func linkified(_ text: String) -> String {
        var output = ""
        var index = text.startIndex
        var previous: Character?

        while index < text.endIndex {
            let rest = text[index...]
            // Markdown 链接目标本身已是 URL，其中内容不应再被当作引用处理。
            if rest.hasPrefix("]("), let close = rest.firstIndex(of: ")") {
                output += text[index...close]
                previous = ")"
                index = text.index(after: close)
            } else if let (link, next) = mention(in: rest, after: previous)
                ?? pullRequest(in: rest, after: previous)
            {
                output += link
                previous = text[text.index(before: next)]
                index = next
            } else {
                output.append(rest[index])
                previous = rest[index]
                index = text.index(after: index)
            }
        }
        return output
    }

    /// 把 `@handle` 提及转为指向 GitHub 个人主页的 Markdown 链接。
    private static func mention(in rest: Substring, after previous: Character?) -> (String, String.Index)? {
        guard rest.first == "@", previous.map({ !$0.isLetter && !$0.isNumber }) ?? true else { return nil }
        let handle = rest.dropFirst().prefix(while: isHandle)
        // 带作用域的包名（如 `@raycast/api`）不是人为提及。
        guard !handle.isEmpty, handle.count <= 39, !handle.hasSuffix("-"),
            rest[handle.endIndex...].first != "/"
        else { return nil }
        return ("[@\(handle)](https://github.com/\(handle))", handle.endIndex)
    }

    /// 把 `#123` 转为指向本仓库对应 Pull Request 的 Markdown 链接。
    private static func pullRequest(
        in rest: Substring, after previous: Character?
    ) -> (String, String.Index)? {
        guard rest.first == "#", previous.map({ $0.isWhitespace || $0 == "(" }) ?? true else { return nil }
        let number = rest.dropFirst().prefix(while: { $0.isASCII && $0.isNumber })
        guard !number.isEmpty else { return nil }
        let url = "https://github.com/\(ReleaseFeed.repository)/pull/\(number)"
        return ("[#\(number)](\(url))", number.endIndex)
    }

    private static func isHandle(_ character: Character) -> Bool {
        character == "-" || (character.isASCII && (character.isLetter || character.isNumber))
    }

    /// 识别无序列表项并返回去掉标记后的文本。
    private static func bullet(in line: String) -> String? {
        guard let marker = line.first, "*-+".contains(marker), line.dropFirst().first == " " else {
            return nil
        }
        return line.dropFirst().trimmingCharacters(in: .whitespaces)
    }
}
