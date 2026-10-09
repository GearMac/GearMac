// 文件职责：决定某个文件在预览面板中由哪种视图绘制（QuickLook / PDF / 媒体 / 纯文本），并在扩展名不足以判断时依据文件头部字节嗵探。
// 分层：Model；纯判定逻辑，不做 IO（字节由调用方传入）。
import Foundation
import UniformTypeIdentifiers

/// 预览区用哪种视图绘制文件。参见 docs/features/file-search.md#palette-and-actions。
enum FileSearchPreviewKind: Equatable, Sendable {
    case quickLook
    /// QuickLook 在进程外绘制 PDF，而那个远端视图在面板里无法滚动。
    case pdf
    /// QuickLook 只绘制影片首帧，在非激活面板中不会播放。
    case media
    /// 文本会被 QuickLook 画成图标：它只把声明为 `public.text` 的内容渲染为文本。
    case text

    /// 当只有字节内容能判断时返回 nil：未声明的类型，或 `.ts`（TypeScript 或 MPEG-TS 视频）。
    init?(pathExtension: String) {
        guard let type = UTType(filenameExtension: pathExtension), !type.isDynamic,
            !type.conforms(to: .mpeg2TransportStream)
        else { return nil }
        self = Self.declared(type)
    }

    /// 用于扩展名无法确定的文件：字节是文本则按文本处理，否则按其声明的类型处理。
    init(pathExtension: String, head: Data, isWholeFile: Bool) {
        guard !Self.isText(head, isWholeFile: isWholeFile) else {
            self = .text
            return
        }
        self = UTType(filenameExtension: pathExtension).map(Self.declared) ?? .quickLook
    }

    private static func declared(_ type: UTType) -> Self {
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .movie) || type.conforms(to: .audio) { return .media }
        return .quickLook
    }

    /// 无 NUL 且为合法 UTF-8；宽容因部分读取而被截断的最后一个多字节字符。
    static func isText(_ bytes: Data, isWholeFile: Bool) -> Bool {
        guard !bytes.contains(0) else { return false }
        let checked = isWholeFile ? bytes : bytes.dropLast(cutCharacterLength(bytes))
        return String(validating: checked, as: UTF8.self) != nil
    }

    /// 末尾多字节字符缺失后续字节时，它已读入的字节数。
    private static func cutCharacterLength(_ bytes: Data) -> Int {
        guard let lead = bytes.suffix(3).lastIndex(where: { $0 & 0xC0 != 0x80 }) else { return 0 }
        let length =
            switch bytes[lead] {
            case 0xC2...0xDF: 2
            case 0xE0...0xEF: 3
            case 0xF0...0xF4: 4
            default: 1
            }
        let present = bytes.endIndex - lead
        return present < length ? present : 0
    }
}
