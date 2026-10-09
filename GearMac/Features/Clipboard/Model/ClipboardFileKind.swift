// 文件职责：描述被引用文件属于哪一类，供类型列显示以及缩略图未生成时的图块使用。
// 分层：Model；保持纯净，不得 import AppKit/SwiftUI，仅依据扩展名判断而不访问磁盘。
import Foundation
import UniformTypeIdentifiers

/// 被引用文件所属的类别，供 Type 行以及缩略图尚未填充时的图块使用。
enum ClipboardFileKind: Sendable {
    case image
    case movie
    case audio
    case pdf
    case folder
    case other

    /// 只依据扩展名解析、从不访问磁盘，因此文件已消失时仍能完成归类。
    static func of(path: String, isDirectory: Bool = false) -> ClipboardFileKind {
        guard !isDirectory else { return .folder }
        let url = URL(filePath: path, directoryHint: .inferFromPath)
        let type = UTType(filenameExtension: url.pathExtension)
        guard let type else { return .other }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) { return .movie }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .pdf) { return .pdf }
        return .other
    }

    /// 预览面板是否直接播放它，而不是绘制一张静帧。
    var isPlayable: Bool { self == .movie || self == .audio }

    /// 按界面语言给出的类型名。
    func localizedTitle(_ language: AppLanguage) -> String {
        let key: ClipboardKey =
            switch self {
            case .image: .fileKindImage
            case .movie: .fileKindMovie
            case .audio: .fileKindAudio
            case .pdf: .fileKindPDF
            case .folder: .fileKindFolder
            case .other: .fileKindOther
            }
        return L10n.string(key, language: language)
    }

    var systemImage: String {
        switch self {
        case .image: return "photo"
        case .movie: return "film"
        case .audio: return "waveform"
        case .pdf: return "doc.richtext"
        case .folder: return "folder"
        case .other: return "doc"
        }
    }
}
