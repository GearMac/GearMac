// 文件职责：Decisions API 的纯模型：判定问题与问题集配置、请求体构造、响应解码与复制用序列化。
// 分层：Model；纯类型与纯函数，不得 import AppKit/SwiftUI。形状错误必须在这里失败，而不是在对话中途。
import Foundation

// MARK: - 配置形状

/// 三种判定问题类型：命题概率、固定选项分类、有序档位评分。
enum DecisionsQuestionKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case predicate
    case choice
    case score

    var id: String { rawValue }
}

/// choice 类型的候选项；`value` 是稳定编码，会原样出现在答案里。
struct DecisionsChoice: Codable, Hashable, Sendable {
    var value: String
    var description: String?
}

/// score 类型的档位；答案 `score` 的值域是 `[0, levels.count - 1]`。
struct DecisionsLevel: Codable, Hashable, Sendable {
    var label: String
    var description: String?
}

/// 用户配置的一个判定问题；choices / levels 仅在对应类型下非空，由校验强制。
struct DecisionsQuestion: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var kind: DecisionsQuestionKind
    var name: String
    var instructions: String
    var choices: [DecisionsChoice]
    var levels: [DecisionsLevel]

    init(
        id: UUID = UUID(), kind: DecisionsQuestionKind, name: String, instructions: String,
        choices: [DecisionsChoice] = [], levels: [DecisionsLevel] = []
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.instructions = instructions
        self.choices = choices
        self.levels = levels
    }

    static func predicate(name: String, instructions: String) -> DecisionsQuestion {
        DecisionsQuestion(kind: .predicate, name: name, instructions: instructions)
    }

    static func choice(
        name: String, instructions: String, choices: [DecisionsChoice]
    ) -> DecisionsQuestion {
        DecisionsQuestion(kind: .choice, name: name, instructions: instructions, choices: choices)
    }

    static func score(
        name: String, instructions: String, levels: [DecisionsLevel]
    ) -> DecisionsQuestion {
        DecisionsQuestion(kind: .score, name: name, instructions: instructions, levels: levels)
    }
}

/// 一组一起发送的判定问题：同一请求内的问题共享同一份 input 且彼此独立判定。
struct DecisionsQuestionSet: Codable, Hashable, Sendable {
    var questions: [DecisionsQuestion]

    init(questions: [DecisionsQuestion] = []) {
        self.questions = questions
    }

    /// 网关与文档共同约定的上限（文档 §3.1：questions 最多 128 个）。
    static let maxQuestions = 128

    /// 默认问题集沿用接入文档 §5.1 的示例结构：情绪、是否需回复、类别与严重度。
    /// 指令保持文档原语言；模型是多语言的，指令语言不影响判定结果的可用性。
    static let standard = DecisionsQuestionSet(questions: [
        .predicate(name: "is_negative", instructions: "这段文本整体是否表达负面评价？"),
        .predicate(name: "needs_reply", instructions: "是否需要在 24 小时内回复这段文本？"),
        .choice(
            name: "category", instructions: "这段文本最主要反映哪类问题？",
            choices: [
                DecisionsChoice(value: "quality", description: "商品破损、做工或功能问题"),
                DecisionsChoice(value: "logistics", description: "发货、配送或包装问题"),
                DecisionsChoice(value: "service", description: "客服或商家态度、响应问题"),
                DecisionsChoice(value: "other", description: "以上都不是"),
            ]),
        .score(
            name: "severity", instructions: "这段文本反映问题的严重程度是什么？",
            levels: [
                DecisionsLevel(label: "轻微", description: "问题不影响主要使用，或可以自行解决"),
                DecisionsLevel(label: "中等", description: "部分功能或体验受影响，但存在替代方案"),
                DecisionsLevel(label: "严重", description: "核心功能不可用，或需要优先人工处理"),
            ]),
    ])
}

// MARK: - 校验

/// 问题集或单个问题不满足网关约束；`message(_:)` 是设置面板展示的文案。
enum DecisionsQuestionError: LocalizedError, Equatable {
    case emptySet
    case tooManyQuestions(Int)
    case nameMissing
    case nameDuplicate(String)
    case instructionsMissing
    case choiceCount(Int)
    case choiceValueEmpty
    case levelCount(Int)
    case levelLabelEmpty

    var errorDescription: String? { message(.english) }

    func message(_ language: AppLanguage) -> String {
        String(
            format: L10n.string(tableKey(language), language: language),
            arguments: formatArguments)
    }

    private func tableKey(_ language: AppLanguage) -> AIKey {
        switch self {
        case .emptySet: return .decisionsValidationEmpty
        case .tooManyQuestions: return .decisionsValidationTooMany
        case .nameMissing: return .decisionsValidationNameMissing
        case .nameDuplicate: return .decisionsValidationNameDuplicate
        case .instructionsMissing: return .decisionsValidationInstructionsMissing
        case .choiceCount: return .decisionsValidationChoiceCount
        case .choiceValueEmpty: return .decisionsValidationChoiceValueEmpty
        case .levelCount: return .decisionsValidationLevelCount
        case .levelLabelEmpty: return .decisionsValidationLevelLabelEmpty
        }
    }

    private var formatArguments: [String] {
        switch self {
        case .tooManyQuestions(let count), .choiceCount(let count), .levelCount(let count):
            return [String(count)]
        case .nameDuplicate(let name): return [name]
        default: return []
        }
    }
}

extension DecisionsQuestion {
    /// 校验单个问题：name 与 instructions 非空，choice 有 2–255 个非空 value，score 有 2–10 个非空 label。
    func validated() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DecisionsQuestionError.nameMissing
        }
        guard !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DecisionsQuestionError.instructionsMissing
        }
        switch kind {
        case .predicate:
            break
        case .choice:
            guard (2...255).contains(choices.count) else {
                throw DecisionsQuestionError.choiceCount(choices.count)
            }
            guard choices.allSatisfy({ !$0.value.trimmingCharacters(in: .whitespaces).isEmpty })
            else { throw DecisionsQuestionError.choiceValueEmpty }
        case .score:
            guard (2...10).contains(levels.count) else {
                throw DecisionsQuestionError.levelCount(levels.count)
            }
            guard levels.allSatisfy({ !$0.label.trimmingCharacters(in: .whitespaces).isEmpty })
            else { throw DecisionsQuestionError.levelLabelEmpty }
        }
    }
}

extension DecisionsQuestionSet {
    /// 校验整个问题集：非空、不超上限、每个问题自身合法且 name 唯一。
    func validated() throws {
        guard !questions.isEmpty else { throw DecisionsQuestionError.emptySet }
        guard questions.count <= Self.maxQuestions else {
            throw DecisionsQuestionError.tooManyQuestions(questions.count)
        }
        var seen: Set<String> = []
        for question in questions {
            try question.validated()
            let key = question.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !seen.contains(key) else {
                throw DecisionsQuestionError.nameDuplicate(question.name)
            }
            seen.insert(key)
        }
    }
}

// MARK: - 路由规则

/// Decisions 的路由规则：模型 id 与端点归一化。
/// 聊天选中一个 Decisions 模型时，请求走 `/decisions` 而不是 `/chat/completions`。
enum DecisionsRouting {
    /// 模型 id 以 `-decisions` 结尾即视为 Decisions 模型（当前为 `openai/gpt-6-luna-decisions`）。
    static func isDecisionsModel(_ model: String) -> Bool {
        model.hasSuffix("-decisions")
    }

    /// 端点归一化：接入文档同时给出「Base URL」与「完整地址」，把完整地址粘进设置时
    /// 剥掉尾部路径，避免拼出 `/decisions/decisions` 这样的重复请求。
    static func normalizeBase(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while true {
            while value.hasSuffix("/") { value.removeLast() }
            if let suffix = ["/decisions", "/models"].first(where: { value.hasSuffix($0) }) {
                value.removeLast(suffix.count)
                continue
            }
            return value
        }
    }
}

// MARK: - 请求体

/// `POST /decisions` 的请求体。刻意保持纯函数：形状写错会在 harness 层失败（文档 §3）。
enum DecisionsRequestBody {
    static func make(
        model: String, input: String, questions: [DecisionsQuestion]
    ) -> [String: Any] {
        [
            "model": model,
            "input": input,
            "questions": questions.map(question),
        ]
    }

    private static func question(_ question: DecisionsQuestion) -> [String: Any] {
        var encoded: [String: Any] = [
            "type": question.kind.rawValue,
            "name": question.name,
            "instructions": question.instructions,
        ]
        switch question.kind {
        case .predicate:
            break
        case .choice:
            encoded["choices"] = question.choices.map { choice in
                var item: [String: Any] = ["value": choice.value]
                if let description = choice.description { item["description"] = description }
                return item
            }
        case .score:
            encoded["levels"] = question.levels.map { level in
                var item: [String: Any] = ["label": level.label]
                if let description = level.description { item["description"] = description }
                return item
            }
        }
        return encoded
    }
}

// MARK: - 响应

/// 答案类型比问题类型多一个 `refusal`：模型拒绝作答时只有 type 与 name（文档 §7.2）。
enum DecisionsAnswerType: String, Decodable, Sendable, Hashable {
    case predicate
    case choice
    case score
    case refusal

    var questionKind: DecisionsQuestionKind? {
        switch self {
        case .predicate: return .predicate
        case .choice: return .choice
        case .score: return .score
        case .refusal: return nil
        }
    }
}

/// 一条概率分布项：choice 的 `value` 是字符串，score 的 `value` 是档位序号并带 `label`。
struct DecisionsProbability: Decodable, Hashable, Sendable {
    let value: String?
    let index: Int?
    let label: String?
    let probability: Double

    private enum CodingKeys: String, CodingKey {
        case value, label, probability
    }

    init(
        value: String? = nil, index: Int? = nil, label: String? = nil, probability: Double
    ) {
        self.value = value
        self.index = index
        self.label = label
        self.probability = probability
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        probability = try container.decode(Double.self, forKey: .probability)
        if let string = try? container.decodeIfPresent(String.self, forKey: .value) {
            value = string
            index = nil
        } else if let number = try? container.decodeIfPresent(Double.self, forKey: .value) {
            value = nil
            index = Int(number)
        } else {
            value = nil
            index = nil
        }
    }
}

/// 一个判定答案。除 type 外字段均可缺：文档明确要求不假设目标字段一定存在。
struct DecisionsAnswer: Decodable, Hashable, Sendable {
    let type: DecisionsAnswerType
    let name: String?
    let probability: Double?
    let choice: String?
    let score: Double?
    let confidence: Double?
    let probabilities: [DecisionsProbability]

    private enum CodingKeys: String, CodingKey {
        case type, name, probability, choice, score, confidence, probabilities
    }

    init(
        type: DecisionsAnswerType, name: String? = nil, probability: Double? = nil,
        choice: String? = nil, score: Double? = nil, confidence: Double? = nil,
        probabilities: [DecisionsProbability] = []
    ) {
        self.type = type
        self.name = name
        self.probability = probability
        self.choice = choice
        self.score = score
        self.confidence = confidence
        self.probabilities = probabilities
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(DecisionsAnswerType.self, forKey: .type)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        probability = try container.decodeIfPresent(Double.self, forKey: .probability)
        choice = try container.decodeIfPresent(String.self, forKey: .choice)
        score = try container.decodeIfPresent(Double.self, forKey: .score)
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
        probabilities =
            try container.decodeIfPresent([DecisionsProbability].self, forKey: .probabilities)
            ?? []
    }

    /// score 落在两档之间时按就近档位取整展示（文档 §4.3：score 是概率加权的连续值）。
    var nearestLevelIndex: Int? {
        guard let score else { return nil }
        return max(0, min(probabilities.count - 1, Int(score.rounded())))
    }
}

struct DecisionsUsage: Decodable, Hashable, Sendable {
    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?

    private enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
    }
}

struct DecisionsResponse: Decodable, Hashable, Sendable {
    let answers: [DecisionsAnswer]
    let usage: DecisionsUsage?

    private enum CodingKeys: String, CodingKey {
        case answers, usage
    }

    init(answers: [DecisionsAnswer], usage: DecisionsUsage? = nil) {
        self.answers = answers
        self.usage = usage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        answers = try container.decodeIfPresent([DecisionsAnswer].self, forKey: .answers) ?? []
        usage = try container.decodeIfPresent(DecisionsUsage.self, forKey: .usage)
    }

    /// 按 name 取答案；answers 的返回顺序没有承诺（文档 §7.1）。
    func answer(named name: String) -> DecisionsAnswer? {
        answers.first { $0.name == name }
    }
}

// MARK: - 复制用序列化

/// 面板 Copy 的纯文本形态；概率按文档口径四舍五入到整百分比。
enum DecisionsResultText {
    static func serialize(
        _ answers: [DecisionsAnswer], usage: DecisionsUsage?, language: AppLanguage
    ) -> String {
        var lines = answers.map { line($0, language: language) }
        if let usage {
            lines.append(
                String(
                    format: L10n.string(AIKey.decisionsCopyTokens, language: language),
                    usage.inputTokens ?? 0, usage.outputTokens ?? 0))
        }
        return lines.joined(separator: "\n")
    }

    private static func line(_ answer: DecisionsAnswer, language: AppLanguage) -> String {
        let name = answer.name ?? "—"
        switch answer.type {
        case .predicate:
            let verdictKey: AIKey =
                (answer.probability ?? 0) >= 0.5 ? .decisionsVerdictYes : .decisionsVerdictNo
            let verdict = L10n.string(verdictKey, language: language)
            return String(
                format: L10n.string(AIKey.decisionsCopyPredicate, language: language),
                name, verdict, Int(((answer.probability ?? 0) * 100).rounded()))
        case .choice:
            let head = String(
                format: L10n.string(AIKey.decisionsCopyChoice, language: language),
                name, answer.choice ?? "—",
                Int(((answer.confidence ?? 0) * 100).rounded()))
            return head + "\n" + distribution(answer.probabilities, language: language)
        case .score:
            let label = label(for: answer)
            let head = String(
                format: L10n.string(AIKey.decisionsCopyScore, language: language),
                name, label,
                answer.score.map { String(format: "%.1f", $0) } ?? "—")
            return head + "\n" + distribution(answer.probabilities, language: language)
        case .refusal:
            return String(
                format: L10n.string(AIKey.decisionsCopyRefused, language: language), name)
        }
    }

    private static func label(for answer: DecisionsAnswer) -> String {
        if let index = answer.nearestLevelIndex,
            answer.probabilities.indices.contains(index),
            let label = answer.probabilities[index].label
        {
            return label
        }
        return answer.probabilities.first?.label ?? "—"
    }

    private static func distribution(
        _ probabilities: [DecisionsProbability], language: AppLanguage
    ) -> String {
        let parts = probabilities.map { probability -> String in
            let key = probability.label ?? probability.value ?? "—"
            return "\(key) \(Int((probability.probability * 100).rounded()))%"
        }
        return "  " + parts.joined(separator: " · ")
    }
}
