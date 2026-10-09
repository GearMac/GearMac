// 文件职责：定义备份中可选类别（配置、剪贴板、代码片段、笔记、学习数据）及其展示描述符。
// 分层：Model；每个类别对应唯一的展示描述符，描述符覆盖全部类别。
import Foundation

/// 备份中一个可单独选择的切片；`descriptor` 覆盖全部类别，与 `AppEntry.Kind` 的做法一致。
enum BackupCategory: String, CaseIterable, Identifiable, Sendable {
    case configuration
    case clipboard
    case snippets
    case notes
    case learning

    var id: Self { self }

    /// 类别的展示信息（名称键、图标、子路径与计数单位键）。
    struct Descriptor: Sendable {
        let labelKey: BackupKey
        let symbol: String
        /// 该类别文件在 bundle 内的位置；为空表示位于 bundle 根目录。
        let subpath: String
        /// 选择器如何为该类别计数；为 nil 表示数字没有意义。
        let countNounKey: BackupKey?

        /// 按语言解析类别名称。
        func label(_ language: AppLanguage) -> String {
            L10n.string(labelKey, language: language)
        }

        /// 按语言解析计数单位；无单位时返回 nil。
        func countNoun(_ language: AppLanguage) -> String? {
            countNounKey.map { L10n.string($0, language: language) }
        }
    }

    /// 该类别的展示描述符。
    var descriptor: Descriptor {
        switch self {
        case .configuration:
            return .init(
                labelKey: .categoryConfiguration, symbol: "slider.horizontal.3", subpath: "",
                countNounKey: nil)
        case .clipboard:
            return .init(
                labelKey: .categoryClipboard, symbol: "doc.on.clipboard", subpath: "clipboard",
                countNounKey: .countClips)
        case .snippets:
            return .init(
                labelKey: .categorySnippets, symbol: "curlybraces", subpath: "snippets",
                countNounKey: .countSnippets)
        case .notes:
            return .init(
                labelKey: .categoryNotes, symbol: "note.text", subpath: "notes",
                countNounKey: .countNotes)
        case .learning:
            return .init(
                labelKey: .categoryLearning, symbol: "chart.line.uptrend.xyaxis",
                subpath: "learning", countNounKey: .countRecords)
        }
    }

    /// 全部类别的集合。
    static let all = Set(BackupCategory.allCases)

    /// 按声明顺序返回，使选择器、manifest 与摘要的列表顺序一致。
    static func ordered(_ selection: Set<BackupCategory>) -> [BackupCategory] {
        allCases.filter(selection.contains)
    }
}
