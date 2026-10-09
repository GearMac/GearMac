// 文件职责：听写模型清单，描述每个模型的族系、变体、下载来源、文件构成与体积。
// 分层：Model/纯数据；只提供静态元数据，不做下载与推理。
import Foundation

/// 可选的听写模型；含 HuggingFace 仓库、revision 与所需文件清单。
enum DictationModel: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Parakeet 模型特有的配置：Joint 模型名、blank token 与编码器是否用 GPU。
    struct ParakeetConfiguration: Sendable {
        let joint: String
        let blankToken: Int
        let encoderUsesGPU: Bool
    }
    /// 模型族系（Parakeet/Qwen）及其简介。
    enum Family: String, CaseIterable, Identifiable {
        case parakeet = "Parakeet", qwen = "Qwen"
        var id: Self { self }
        /// 族系的一句话说明。
        func summary(_ language: AppLanguage) -> String {
            L10n.string(
                self == .parakeet ? DictationKey.familyParakeetSummary : DictationKey.familyQwenSummary,
                language: language)
        }
    }
    case redux
    case ultra
    case qwenSmall = "qwen-0.6b"
    case qwenLarge = "qwen-1.7b"

    var id: Self { self }
    /// 完整标题：族系 + 变体名。
    var title: String { "\(family.rawValue) · \(variantTitle)" }
    /// 变体的短名（Ultra/Redux/0.6B/1.7B）。
    var variantTitle: String {
        switch self {
        case .ultra: "Ultra"
        case .redux: "Redux"
        case .qwenSmall: "0.6B"
        case .qwenLarge: "1.7B"
        }
    }

    /// 面向设置的模型简介。
    func summary(_ language: AppLanguage) -> String {
        let key: DictationKey
        switch self {
        case .redux: key = .summaryRedux
        case .ultra: key = .summaryUltra
        case .qwenSmall: key = .summaryQwenSmall
        case .qwenLarge: key = .summaryQwenLarge
        }
        return L10n.string(key, language: language)
    }

    /// 该模型所属族系。
    var family: Family {
        switch self {
        case .ultra, .redux: .parakeet
        case .qwenSmall, .qwenLarge: .qwen
        }
    }
    /// 是否属于 Qwen 族系。
    var isQwen: Bool { family == .qwen }
    /// Parakeet 模型的专属配置；Qwen 模型为 nil。
    var parakeetConfiguration: ParakeetConfiguration? {
        switch self {
        case .ultra, .redux:
            .init(joint: "JointDecisionv3", blankToken: 8192, encoderUsesGPU: self == .redux)
        case .qwenSmall, .qwenLarge: nil
        }
    }
    /// 支持的语言覆盖范围描述。
    func coverage(_ language: AppLanguage) -> String {
        switch self {
        case .ultra, .redux: return L10n.string(DictationKey.coverageParakeet, language: language)
        case .qwenSmall, .qwenLarge: return L10n.string(DictationKey.coverageQwen, language: language)
        }
    }
    /// 本地缓存目录名。
    var folderName: String { isQwen ? rawValue : "parakeet-\(rawValue)" }
    /// 安装后占用的大致体积（MB）。
    var approximateInstalledMegabytes: Int {
        switch self {
        case .ultra: 632
        case .redux: 220
        case .qwenSmall: 940
        case .qwenLarge: 2352
        }
    }

    /// 模型必须存在的顶层文件/目录集合。
    var components: Set<String> {
        if isQwen { return ["encoder.mlmodelc", "decoder.mlmodelc", "embedding.mlmodelc", "config.json"] }
        guard let configuration = parakeetConfiguration else { return [] }
        return [
            "Preprocessor.mlmodelc", "Encoder.mlmodelc", "Decoder.mlmodelc",
            configuration.joint + ".mlmodelc", "parakeet_vocab.json"
        ]
    }

    /// 判定「已安装」所需的全部文件（含分词器资源）。
    var requiredFiles: Set<String> { components.union(isQwen ? ["vocab.json", "merges.txt"] : []) }

    /// HuggingFace 仓库标识。
    var repository: String {
        switch self {
        case .ultra, .redux: "FluidInference/\(folderName)-coreml"
        case .qwenSmall: "UniMocha/Qwen3-ASR-0.6B-CoreML-INT8"
        case .qwenLarge: "UniMocha/Qwen3-ASR-1.7B-CoreML-INT8"
        }
    }

    /// 拉取时锁定的 commit 版本。
    var revision: String {
        switch self {
        case .ultra: "95eaa59a39d4394f047a4dc5cce480388a60d1b6"
        case .redux: "8c5ef97a29cd120dc76b354b3f22b7fec3b486f9"
        case .qwenSmall: "27b7a26835d7c2cd1cf774b4c490eb5519ca71a0"
        case .qwenLarge: "06312fbac1383cd22e1000c28b017634e03251a2"
        }
    }
}
