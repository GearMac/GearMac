// 文件职责：定义 `.gearmac` 备份负载的目录布局与读写辅助方法。
// 分层：Model；只负责文件布局与编解码，不处理归档与 UI。
import Foundation

/// `.gearmac` 归档所封装的负载；保持纯粹，便于测试直接使用真实布局。
struct BackupBundle: Sendable {
    /// 学习数据中可备份的各个部分。
    enum LearningPart: String, CaseIterable, Sendable {
        case ranking
        case emoji
        case calculator
    }

    let root: URL

    init(root: URL) {
        self.root = root
    }

    // MARK: - Layout

    var manifestURL: URL { root.appendingPathComponent("manifest.json") }
    var settingsURL: URL { root.appendingPathComponent("settings.json") }

    private func directory(for category: BackupCategory) -> URL {
        let subpath = category.descriptor.subpath
        guard !subpath.isEmpty else { return root }
        return root.appendingPathComponent(subpath, isDirectory: true)
    }

    var clipboardItemsURL: URL { directory(for: .clipboard).appendingPathComponent("items.jsonl") }
    var clipboardImagesDirectory: URL {
        directory(for: .clipboard).appendingPathComponent("images", isDirectory: true)
    }
    var snippetsDirectory: URL { directory(for: .snippets) }
    var notesDirectory: URL { directory(for: .notes) }

    func learningURL(_ part: LearningPart) -> URL {
        directory(for: .learning).appendingPathComponent("\(part.rawValue).json")
    }

    // MARK: - Writing

    /// 在组装前调用一次；归档只包含被请求的类别对应的目录。
    func prepare(_ categories: Set<BackupCategory>) throws {
        try create(root)
        if categories.contains(.clipboard) { try create(clipboardImagesDirectory) }
        if categories.contains(.snippets) { try create(snippetsDirectory) }
        if categories.contains(.notes) { try create(notesDirectory) }
        if categories.contains(.learning) { try create(directory(for: .learning)) }
    }

    func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    func writeManifest(_ manifest: BackupManifest) throws {
        try write(try Self.encoder.encode(manifest), to: manifestURL)
    }

    func encode<Value: Encodable>(_ value: Value, to url: URL) throws {
        try write(try Self.encoder.encode(value), to: url)
    }

    /// 返回实际使用的文件名；重名或不安全的标题会被去重处理，绝不丢弃。
    @discardableResult
    func writeDocument(
        title: String, extension ext: String, contents: String, in directory: URL
    )
        throws -> String
    {
        let name = uniqueName(base: Self.sanitized(title), extension: ext, in: directory)
        try write(Data(contents.utf8), to: directory.appendingPathComponent(name))
        return name
    }

    // MARK: - Clipboard, a line at a time

    /// 每行一条剪贴板记录；记录内部的换行会被转义，因此 `\n` 只会作为分隔符出现。
    struct ClipboardWriter: ~Copyable {
        private let handle: FileHandle
        /// 输出紧凑而非美化格式：美化后的对象会跨行，破坏逐行分隔。
        private let encoder: JSONEncoder

        init(url: URL) throws {
            FileManager.default.createFile(atPath: url.path, contents: nil)
            handle = try FileHandle(forWritingTo: url)
            encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
        }

        func write(_ item: BackupClipboardItem) throws {
            var line = try encoder.encode(item)
            line.append(0x0A)
            try handle.write(contentsOf: line)
        }

        deinit { try? handle.close() }
    }

    func clipboardWriter() throws -> ClipboardWriter {
        try ClipboardWriter(url: clipboardItemsURL)
    }

    /// 采用内存映射并惰性解码，因此即使 GB 级历史也只占用一条记录的常驻内存。
    func clipboardItems() -> some Sequence<BackupClipboardItem> {
        let data = (try? Data(contentsOf: clipboardItemsURL, options: .mappedIfSafe)) ?? Data()
        return data.split(separator: 0x0A, omittingEmptySubsequences: true)
            .lazy
            .compactMap { try? Self.decoder.decode(BackupClipboardItem.self, from: Data($0)) }
    }

    // MARK: - Reading

    /// 读取并校验 manifest，格式版本不受支持时抛错。
    func readManifest() throws(BackupFormatError) -> BackupManifest {
        guard let data = try? Data(contentsOf: manifestURL),
            let manifest = try? Self.decoder.decode(BackupManifest.self, from: data)
        else { throw .unreadable }
        guard manifest.format == BackupManifest.currentFormat else {
            throw .unsupportedFormat(found: manifest.format)
        }
        return manifest
    }

    /// 返回 nil 而非抛错：归档中缺失图片的剪贴板记录会被跳过并计数。
    func clipboardImageURL(named name: String) -> URL? {
        guard Self.isSafeName(name) else { return nil }
        let url = clipboardImagesDirectory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// 按扩展名读取目录下的文档，按名称排序。
    func documents(in directory: URL, extension ext: String) -> [(name: String, contents: String)] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.sorted().compactMap { name in
            guard Self.isSafeName(name), (name as NSString).pathExtension == ext,
                let contents = try? String(
                    contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
            else { return nil }
            return (name, contents)
        }
    }

    /// 从学习数据文件中解码指定部分，失败时返回 nil。
    func decodeLearning<Value: Decodable>(_ part: LearningPart, as type: Value.Type) -> Value? {
        guard let data = try? Data(contentsOf: learningURL(part)) else { return nil }
        return try? Self.decoder.decode(Value.self, from: data)
    }

    // MARK: - Coding

    /// 备份中的日期统一使用 ISO-8601 编码，便于人工阅读与路工具解析。
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - Names

    /// 笔记或代码片段标题在此转成文件名，因此路径分隔符无法保留。
    static func sanitized(_ title: String) -> String {
        let cleaned = title.components(separatedBy: Self.forbidden).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // 开头的点会隐藏文件，也可能拼出 `..`；结果为空时仍需给一个名字。
        let trimmed = String(cleaned.drop { $0 == "." }.prefix(120))
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    /// 判断文件名是否安全（非空、非 `.`/`..`、不含禁止字符）。
    static func isSafeName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".."
            && name.rangeOfCharacter(from: Self.forbidden) == nil
    }

    /// 文件名中禁止出现的字符集合。
    private static let forbidden = CharacterSet(charactersIn: "/:\\\0")

    private func uniqueName(base: String, extension ext: String, in directory: URL) -> String {
        var candidate = "\(base).\(ext)"
        var suffix = 1
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            suffix += 1
            candidate = "\(base) \(suffix).\(ext)"
        }
        return candidate
    }

    private func create(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
