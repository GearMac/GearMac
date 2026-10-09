// 文件职责：解析 Raycast 脚本命令目录（读取 shebang 与 `@raycast.*` 指令），将其转换为 CustomCommand 草稿。
// 分层：Model；仅依赖 Foundation，读取文件但不执行脚本，扫描为 nonisolated 且不递归子目录。
import Foundation

/// 把一整个 Raycast 脚本目录读取为草稿。详见 docs/features/custom-commands.md。
enum RaycastScriptImport {
    private static let headSize = 8 * 1024
    private static let directivePrefix = "@raycast."
    /// shell 模板用 `#`，JavaScript 与 Swift 用 `//`，AppleScript 用 `--`。
    private static let commentMarkers = ["#", "//", "--"]

    /// 与 Raycast 自身的脚本目录一致，不递归子目录；非脚本命令的文件会被跳过。
    nonisolated static func scan(
        directory: URL, fileManager: FileManager = .default
    ) -> [CustomCommand] {
        let contents =
            (try? fileManager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])) ?? []
        return
            contents
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                // 符号链接报告的是自身类型而非目标类型，而脚本目录常以链接形式存在。
                guard isRegularFile(url) || isRegularFile(url.resolvingSymlinksInPath()),
                    let source = head(of: url)
                else { return nil }
                return command(at: url, source: source)
            }
    }

    /// 判断 URL 是否指向普通文件（路径不存在时返回 false）。
    private static func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    /// 当文件既声明了解释器又声明了 title 时，才算一个脚本命令。
    nonisolated static func command(at url: URL, source: String) -> CustomCommand? {
        guard let interpreter = shebang(in: source) else { return nil }
        let directives = directives(in: source)
        guard let title = directives["title"] else { return nil }
        // 运行器传入的取值落在 zsh 的位置参数表上；不转发的话脚本将看不到任何参数。
        return CustomCommand(
            name: title,
            command: "\(interpreter) \(shellQuoted(url.path)) \"$@\"",
            requiresConfirmation: directives["needsConfirmation"] == "true",
            arguments: arguments(in: directives),
            showsOutput: showsOutput(mode: directives["mode"]),
            workingDirectory: workingDirectory(directives["currentDirectoryPath"], script: url))
    }

    /// Raycast 要求必须有 shebang；显式写出解释器而非依赖可执行位，可避免改动原文件。
    private static func shebang(in source: String) -> String? {
        let first = source.prefix { !$0.isNewline }
        guard first.hasPrefix("#!") else { return nil }
        let interpreter = first.dropFirst(2).trimmingCharacters(in: .whitespacesAndNewlines)
        return interpreter.isEmpty ? nil : interpreter
    }

    /// 指令块在代码开始处结束；再往后出现的 `@raycast.` 只属于脚本自己的正文。
    private static func directives(in source: String) -> [String: String] {
        var values: [String: String] = [:]
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            guard let body = commentBody(trimmed) else { break }
            guard body.hasPrefix(directivePrefix) else { continue }
            let field = body.dropFirst(directivePrefix.count)
            guard let separator = field.firstIndex(where: \.isWhitespace) else { continue }
            let key = String(field[..<separator])
            let value = field[separator...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { continue }
            values[key] = value
        }
        return values
    }

    /// 去掉行首注释标记并返回剩余正文；不是注释行时返回 nil。
    private static func commentBody(_ line: String) -> String? {
        guard let marker = commentMarkers.first(where: line.hasPrefix) else { return nil }
        return line.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
    }

    /// `silent` 与 `inline` 无需展示输出；另外两种输出模式才会打开窗口。
    private static func showsOutput(mode: String?) -> Bool {
        mode == "compact" || mode == "fullOutput"
    }

    /// Raycast 最多允许三个，每个是 JSON 对象，其 placeholder 即我们使用的提示文案。
    private static func arguments(in directives: [String: String]) -> [CustomCommandArgument] {
        (1...3).compactMap { index in
            guard let json = directives["argument\(index)"]?.data(using: .utf8),
                let object = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any],
                let placeholder = object["placeholder"] as? String, !placeholder.isEmpty
            else { return nil }
            return CustomCommandArgument(
                name: placeholder, isOptional: object["optional"] as? Bool ?? false)
        }
    }

    /// 除非脚本另有声明，否则使用脚本自身所在目录——这也是其相对路径的基准。
    private static func workingDirectory(_ declared: String?, script: URL) -> String {
        let path = declared ?? script.deletingLastPathComponent().path
        return (path as NSString).abbreviatingWithTildeInPath
    }

    /// 使用单引号包裹，使含空格、`$` 或引号的路径对 zsh 仍是单个词。
    private static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// shebang 与指令都在文件开头，而正文可能有数 MB，因此只读头部。
    private static func head(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard var data = try? handle.read(upToCount: headSize), !data.isEmpty else { return nil }
        // 截断落在换行符处：多字节字符内部不会包含换行，而按长度截断会切在行中间。
        if data.count == headSize, let end = data.lastIndex(of: UInt8(ascii: "\n")) {
            data = data[..<end]
        }
        return String(bytes: data, encoding: .utf8)
    }
}
