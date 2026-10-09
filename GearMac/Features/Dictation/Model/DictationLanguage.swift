// 文件职责：听写支持的语言列表（Qwen 模型的可选语言）。
// 分层：Model/纯枚举；rawValue 与模型 prompt 中的语言名一致。
import Foundation

/// Qwen 识别器可指定的语言；rawValue 直接用于 prompt 中的语言标记。
enum DictationLanguage: String, CaseIterable, Identifiable, Sendable {
    case arabic = "Arabic", cantonese = "Cantonese", chinese = "Chinese", czech = "Czech"
    case danish = "Danish", dutch = "Dutch", english = "English", filipino = "Filipino"
    case finnish = "Finnish", french = "French", german = "German", greek = "Greek"
    case hindi = "Hindi", hungarian = "Hungarian", indonesian = "Indonesian", italian = "Italian"
    case japanese = "Japanese", korean = "Korean", macedonian = "Macedonian", malay = "Malay"
    case persian = "Persian", polish = "Polish", portuguese = "Portuguese", romanian = "Romanian"
    case russian = "Russian", spanish = "Spanish", swedish = "Swedish", thai = "Thai"
    case turkish = "Turkish", vietnamese = "Vietnamese"

    var id: Self { self }

    /// 显示名对应的本地化键；rawValue 仍用于模型提示，因此不直接展示它。
    private var displayKey: DictationLanguageKey {
        switch self {
        case .arabic: return .arabic
        case .cantonese: return .cantonese
        case .chinese: return .chinese
        case .czech: return .czech
        case .danish: return .danish
        case .dutch: return .dutch
        case .english: return .english
        case .filipino: return .filipino
        case .finnish: return .finnish
        case .french: return .french
        case .german: return .german
        case .greek: return .greek
        case .hindi: return .hindi
        case .hungarian: return .hungarian
        case .indonesian: return .indonesian
        case .italian: return .italian
        case .japanese: return .japanese
        case .korean: return .korean
        case .macedonian: return .macedonian
        case .malay: return .malay
        case .persian: return .persian
        case .polish: return .polish
        case .portuguese: return .portuguese
        case .romanian: return .romanian
        case .russian: return .russian
        case .spanish: return .spanish
        case .swedish: return .swedish
        case .thai: return .thai
        case .turkish: return .turkish
        case .vietnamese: return .vietnamese
        }
    }

    /// 界面上展示的语言名。
    func displayName(_ language: AppLanguage) -> String {
        L10n.string(displayKey, language: language)
    }
}
