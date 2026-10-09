// 文件职责：定义「搜索文件」面板顶部的类型筛选器（全部、文件夹、文档、图片、音频、视频、压缩包）及其类型判定规则。
// 分层：Model；纯值与纯函数，不引入副作用，也不 import AppKit/SwiftUI。
import Foundation
import UniformTypeIdentifiers

/// 「搜索文件」面板顶部的类型筛选器。参见 docs/features/file-search.md#type-filter。
enum FileSearchFilter: CaseIterable, Sendable {
    case all
    case folders
    case documents
    case images
    case audio
    case video
    case archives

    /// 筛选器的显示名称。
    func localizedTitle(_ language: AppLanguage) -> String {
        switch self {
        case .all: return L10n.string(FileSearchKey.filterAll, language: language)
        case .folders: return L10n.string(FileSearchKey.filterFolders, language: language)
        case .documents: return L10n.string(FileSearchKey.filterDocuments, language: language)
        case .images: return L10n.string(FileSearchKey.filterImages, language: language)
        case .audio: return L10n.string(FileSearchKey.filterAudio, language: language)
        case .video: return L10n.string(FileSearchKey.filterVideo, language: language)
        case .archives: return L10n.string(FileSearchKey.filterArchives, language: language)
        }
    }

    /// 同时作为顶部按钮的图标，因此不展开菜单也能看出当前生效的筛选类型。
    var systemImage: String {
        switch self {
        case .all: return "list.bullet"
        case .folders: return "folder"
        case .documents: return "doc.text"
        case .images: return "photo"
        case .audio: return "waveform"
        case .video: return "film"
        case .archives: return "archivebox"
        }
    }

    /// 列表为空时展示的文案，让「筛选条件过滤掉了全部匹配」这件事自解释。
    func localizedEmptyMessage(_ language: AppLanguage) -> String {
        switch self {
        case .all: return L10n.string(FileSearchKey.emptyAll, language: language)
        case .folders: return L10n.string(FileSearchKey.emptyFolders, language: language)
        case .documents: return L10n.string(FileSearchKey.emptyDocuments, language: language)
        case .images: return L10n.string(FileSearchKey.emptyImages, language: language)
        case .audio: return L10n.string(FileSearchKey.emptyAudio, language: language)
        case .video: return L10n.string(FileSearchKey.emptyVideo, language: language)
        case .archives: return L10n.string(FileSearchKey.emptyArchives, language: language)
        }
    }

    /// 该分支接受的类型；`all` 不指定任何类型，因此未筛选的搜索不受类型限制。
    var contentTypes: [UTType] {
        switch self {
        case .all: return []
        case .folders: return [.folder]
        case .documents: return [.text, .compositeContent, .spreadsheet, .presentation, .pdf]
        case .images: return [.image]
        case .audio: return [.audio]
        case .video: return [.movie]
        case .archives: return [.archive]
        }
    }

    /// 把类型过滤放进查询谓词，避免被排除的类型占用候选数量上限。
    var spotlightClause: String? {
        let clauses = contentTypes.map { "kMDItemContentTypeTree == \"\($0.identifier)\"" }
        guard let first = clauses.first else { return nil }
        guard clauses.count > 1 else { return first }
        return "(" + clauses.joined(separator: " || ") + ")"
    }

    /// 家目录根部这一分支不会经过 Spotlight，因此在本地回答同样的类型判断。
    func accepts(contentType: UTType?, isDirectory: Bool) -> Bool {
        guard self != .all else { return true }
        // 类型未解析时只可能是普通目录：其他条目都带有类型信息。
        guard let contentType else { return self == .folders && isDirectory }
        return contentTypes.contains { contentType.conforms(to: $0) }
    }
}
