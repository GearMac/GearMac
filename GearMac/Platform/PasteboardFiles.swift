// 文件职责：从剪贴板读取文件 URL 列表（含旧式文件名校验回退），以及把文件写入剪贴板。
// 分层：Service；仅依赖 AppKit 剪贴板 API，不持有状态。
import AppKit

/// 剪贴板中列出的文件；`NSURL` 读取会自行选择一种表示形式。
enum PasteboardFiles {
    /// 由仍使用 UTI 之前剪贴板格式的程序写入。
    private static let legacyFilenames = NSPasteboard.PasteboardType("NSFilenamesPboardType")

    /// 把文件本身放上剪贴板，从而在 Finder 中粘贴会复制文件而非其路径。
    static func write(_ url: URL, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.declareTypes([.fileURL, .string], owner: nil)
        pasteboard.setData(url.dataRepresentation, forType: .fileURL)
        // 同时写入两种类型：接收文件的应用拿到文件，文本框拿到路径。
        pasteboard.setString(url.path, forType: .string)
    }

    /// 剪贴板未命名任何文件时返回空，使调用方回退到文本或字节处理。
    static func urls(on pasteboard: NSPasteboard) -> [URL] {
        urls(on: pasteboard, limit: .max) { _ in true }
    }

    /// 边解码边过滤，使得一次选中上万文件时能在达到上限处停止解码。
    static func urls(
        on pasteboard: NSPasteboard, limit: Int, matching predicate: (URL) -> Bool
    ) -> [URL] {
        guard limit > 0 else { return [] }
        var matches: [URL] = []
        var hasFileURL = false
        for item in pasteboard.pasteboardItems ?? [] {
            guard let url = url(from: item) else { continue }
            hasFileURL = true
            guard predicate(url) else { continue }
            matches.append(url)
            if matches.count == limit { return matches }
        }
        // 现代格式存在时会抑制回退，即使每个 URL 都被拒绝了。
        guard !hasFileURL,
            let paths = pasteboard.propertyList(forType: legacyFilenames) as? [String]
        else { return matches }
        for path in paths {
            let url = URL(fileURLWithPath: path)
            guard predicate(url) else { continue }
            matches.append(url)
            if matches.count == limit { return matches }
        }
        return matches
    }

    /// `public.file-url` 在多数剪贴板中以 UTF-8 数据到位，在少数情况下以字符串形式出现。
    private static func url(from item: NSPasteboardItem) -> URL? {
        if let data = item.data(forType: .fileURL),
            let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL
        {
            return url
        }
        guard let string = item.string(forType: .fileURL), let url = URL(string: string),
            url.isFileURL
        else { return nil }
        return url
    }
}
