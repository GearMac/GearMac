// 文件职责：验证 Decisions API 的纯逻辑：请求体形状、问题集校验、响应解码（含 refusal）与复制序列化。
// 分层：测试 harness；直接编译真实源码，无 UI、无网络、无共享状态。

import Foundation

/// 验证 Decisions 纯逻辑的测试入口。
@main
@MainActor
struct DecisionsTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    /// 依次运行全部 Decisions 用例并汇总结果。
    static func main() {
        defaultSetShipsValidAndFaithful()
        requestBodiesMatchTheDocumentedShape()
        validationCatchesEveryDocumentedConstraint()
        validationMessagesNameTheirOwnCause()
        answersDecodeFromTheDocumentedResponse()
        decodingToleratesMissingFields()
        scoresRoundToTheirNearestLevel()
        answersAreFoundByNameNeverByOrder()
        serializationIsStableInBothLanguages()
        questionSetsSurviveARoundTrip()
        pastedFullAddressesNormalizeToTheBase()
        decisionsModelsRouteThemselves()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    /// 默认问题集必须开箱合法，且与接入文档 §5.1 的示例一一对应。
    static func defaultSetShipsValidAndFaithful() {
        let set = DecisionsQuestionSet.standard
        expect((try? set.validated()) != nil, "standard set validates")
        expect(set.questions.count == 4, "standard set has four questions")
        expect(
            set.questions.map(\.kind) == [.predicate, .predicate, .choice, .score],
            "standard set covers every kind")
        expect(set.answerNames() == ["is_negative", "needs_reply", "category", "severity"],
            "standard set keeps the documented names")
        let category = set.questions.first { $0.name == "category" }
        expect(category?.choices.map(\.value) == ["quality", "logistics", "service", "other"],
            "standard choices match the document")
        let severity = set.questions.first { $0.name == "severity" }
        expect(severity?.levels.map(\.label) == ["轻微", "中等", "严重"],
            "standard levels match the document")
    }

    /// 请求体必须逐字段对齐文档 §3/§4：type/name/instructions，choice 带 choices，score 带 levels。
    static func requestBodiesMatchTheDocumentedShape() {
        let body = DecisionsRequestBody.make(
            model: "openai/gpt-6-luna-decisions",
            input: "这件衣服质量太差了，拉链第一天就坏了！",
            questions: DecisionsQuestionSet.standard.questions)

        expect(body["model"] as? String == "openai/gpt-6-luna-decisions", "model rides along")
        expect(
            body["input"] as? String == "这件衣服质量太差了，拉链第一天就坏了！",
            "input rides along")
        let questions = body["questions"] as? [[String: Any]]
        expect(questions?.count == 4, "four questions encoded")

        let predicate = questions?[0]
        expect(predicate?["type"] as? String == "predicate", "predicate type encoded")
        expect(predicate?["name"] as? String == "is_negative", "predicate name encoded")
        expect(
            (predicate?["instructions"] as? String)?.isEmpty == false,
            "predicate instructions encoded")
        expect(
            predicate.map { Set($0.keys) } == Set(["type", "name", "instructions"]),
            "predicate carries no extra keys")

        let choice = questions?[2]
        let choices = choice?["choices"] as? [[String: Any]]
        expect(choices?.count == 4, "choice options encoded")
        expect(choices?[0]["value"] as? String == "quality", "choice value encoded")
        expect(
            (choices?[0]["description"] as? String)?.isEmpty == false,
            "choice description encoded")
        expect(
            choice.map { Set($0.keys) } == Set(["type", "name", "instructions", "choices"]),
            "choice carries choices and no levels")

        let score = questions?[3]
        let levels = score?["levels"] as? [[String: Any]]
        expect(levels?.count == 3, "score levels encoded")
        expect(levels?[0]["label"] as? String == "轻微", "score label encoded")
        expect(
            score.map { Set($0.keys) } == Set(["type", "name", "instructions", "levels"]),
            "score carries levels and no choices")

        expect(
            Set(body.keys) == Set(["model", "input", "questions"]),
            "body carries only the documented top-level keys")
    }

    /// 文档 §9 的每条约束都必须在发出请求前被拦截。
    static func validationCatchesEveryDocumentedConstraint() {
        func error<T>(_ block: () throws -> T) -> DecisionsQuestionError? {
            do {
                _ = try block()
                return nil
            } catch let e as DecisionsQuestionError {
                return e
            } catch {
                return nil
            }
        }

        expect(
            error({ try DecisionsQuestionSet(questions: []).validated() }) == .emptySet,
            "empty set refused")
        let tooMany = DecisionsQuestionSet(
            questions: (0...DecisionsQuestionSet.maxQuestions).map {
                DecisionsQuestion.predicate(name: "q\($0)", instructions: "i")
            })
        expect(
            error({ try tooMany.validated() }) == .tooManyQuestions(129),
            "129 questions refused with the count")

        expect(
            error({ try DecisionsQuestion.predicate(name: "  ", instructions: "i").validated() })
                == .nameMissing,
            "blank name refused")
        expect(
            error({
                try DecisionsQuestionSet(questions: [
                    .predicate(name: "dup", instructions: "i"),
                    .predicate(name: "dup", instructions: "i"),
                ]).validated()
            }) == .nameDuplicate("dup"),
            "duplicate name refused with the name")
        expect(
            error({ try DecisionsQuestion.predicate(name: "n", instructions: " ").validated() })
                == .instructionsMissing,
            "blank instructions refused")

        expect(
            error({
                try DecisionsQuestion.choice(
                    name: "n", instructions: "i",
                    choices: [DecisionsChoice(value: "a", description: nil)]).validated()
            }) == .choiceCount(1),
            "one choice refused with the count")
        expect(
            error({
                try DecisionsQuestion.choice(
                    name: "n", instructions: "i",
                    choices: (0..<256).map { DecisionsChoice(value: "c\($0)", description: nil) })
                    .validated()
            }) == .choiceCount(256),
            "256 choices refused with the count")
        expect(
            error({
                try DecisionsQuestion.choice(
                    name: "n", instructions: "i",
                    choices: [
                        DecisionsChoice(value: "a", description: nil),
                        DecisionsChoice(value: " ", description: nil),
                    ]).validated()
            }) == .choiceValueEmpty,
            "blank choice value refused")

        expect(
            error({
                try DecisionsQuestion.score(
                    name: "n", instructions: "i", levels: [DecisionsLevel(label: "l")])
                    .validated()
            }) == .levelCount(1),
            "one level refused with the count")
        expect(
            error({
                try DecisionsQuestion.score(
                    name: "n", instructions: "i",
                    levels: (0..<11).map { DecisionsLevel(label: "l\($0)") }).validated()
            }) == .levelCount(11),
            "eleven levels refused with the count")
        expect(
            error({
                try DecisionsQuestion.score(
                    name: "n", instructions: "i",
                    levels: [DecisionsLevel(label: "l"), DecisionsLevel(label: " ")]).validated()
            }) == .levelLabelEmpty,
            "blank level label refused")

        let boundary = DecisionsQuestionSet(questions: [
            .choice(
                name: "c", instructions: "i",
                choices: (0..<255).map { DecisionsChoice(value: "v\($0)", description: nil) }),
            .score(
                name: "s", instructions: "i",
                levels: (0..<10).map { DecisionsLevel(label: "L\($0)") }),
        ])
        expect((try? boundary.validated()) != nil, "255 choices and 10 levels are accepted")
    }

    /// 每条校验文案都要说明自己的原因；笼统的「无效」会把编辑器变成猜谜。
    static func validationMessagesNameTheirOwnCause() {
        let errors: [DecisionsQuestionError] = [
            .emptySet, .tooManyQuestions(129), .nameMissing, .nameDuplicate("dup"),
            .instructionsMissing, .choiceCount(1), .choiceValueEmpty, .levelCount(1),
            .levelLabelEmpty,
        ]
        let messages = errors.map { $0.message(.english) }
        expect(Set(messages).count == errors.count, "no two validation errors read the same")
        expect(
            errors.allSatisfy { $0.message(.chinese) != $0.message(.english) },
            "every validation error has a Chinese reading")
    }

    /// 文档 §5.1 的完整响应必须原样解出：三种答案、refusal 与 usage。
    static func answersDecodeFromTheDocumentedResponse() {
        let response = decodeResponse(DecisionsFixtures.documentedResponse)

        expect(response.answers.count == 4, "four answers decoded")

        let negative = response.answer(named: "is_negative")
        expect(negative?.type == .predicate, "predicate type decoded")
        expect(negative?.probability == 0.99, "predicate probability decoded")

        let category = response.answer(named: "category")
        expect(category?.type == .choice, "choice type decoded")
        expect(category?.choice == "quality", "choice winner decoded")
        expect(category?.confidence == 0.88, "choice confidence decoded")
        expect(category?.probabilities.count == 4, "choice distribution decoded")
        expect(
            category?.probabilities.first?.value == "quality"
                && category?.probabilities.first?.probability == 0.91,
            "choice distribution keeps value and probability")
        expect(
            category?.probabilities.first?.index == nil,
            "a string value never masquerades as an index")

        let severity = response.answer(named: "severity")
        expect(severity?.type == .score, "score type decoded")
        expect(severity?.score == 1.0, "score value decoded")
        expect(severity?.confidence == 0.87, "score confidence decoded")
        expect(severity?.probabilities.count == 3, "score distribution decoded")
        expect(
            severity?.probabilities.first?.index == 0
                && severity?.probabilities.first?.label == "轻微"
                && severity?.probabilities.first?.probability == 0.06,
            "score distribution keeps index, label and probability")
        expect(
            severity?.probabilities.first?.value == nil,
            "a numeric index never masquerades as a value")

        let reply = response.answer(named: "needs_reply")
        expect(reply?.type == .refusal, "refusal type decoded")
        expect(reply?.probability == nil && reply?.choice == nil && reply?.score == nil,
            "refusal carries no verdict fields")

        expect(response.usage?.inputTokens == 520, "usage input tokens decoded")
        expect(response.usage?.outputTokens == 0, "usage output tokens decoded")
        expect(response.usage?.totalTokens == 520, "usage total tokens decoded")
    }

    /// 文档 §7.2：不要假设目标字段一定存在；answers/probabilities 缺失时按空处理。
    static func decodingToleratesMissingFields() {
        let bare = decodeResponse(#"{"answers": [{"type": "predicate", "name": "p"}]}"#)
        expect(bare.answers.count == 1, "answer without probability still decodes")
        expect(bare.answers[0].probability == nil, "missing probability stays nil")
        expect(bare.answers[0].probabilities.isEmpty, "missing probabilities stay empty")

        let empty = decodeResponse("{}")
        expect(empty.answers.isEmpty, "missing answers decode to empty")
        expect(empty.usage == nil, "missing usage stays nil")
    }

    /// score 是概率加权的连续值；展示档位按就近取整并夹在分布范围内。
    static func scoresRoundToTheirNearestLevel() {
        func answer(_ score: Double?, probabilities: Int) -> DecisionsAnswer {
            DecisionsAnswer(
                type: .score, name: "s", score: score,
                probabilities: (0..<probabilities).map {
                    DecisionsProbability(index: $0, label: "L\($0)", probability: 0)
                })
        }
        expect(answer(1.0, probabilities: 3).nearestLevelIndex == 1, "1.0 lands on the middle")
        expect(answer(0.8, probabilities: 3).nearestLevelIndex == 1, "0.8 leans to the middle")
        expect(answer(2.7, probabilities: 3).nearestLevelIndex == 2, "2.7 clamps to the last")
        expect(answer(nil, probabilities: 3).nearestLevelIndex == nil, "no score, no level")
        expect(answer(9.0, probabilities: 3).nearestLevelIndex == 2, "out-of-range clamps")
    }

    /// answers 的返回顺序没有承诺；按 name 取值必须与顺序无关。
    static func answersAreFoundByNameNeverByOrder() {
        let response = decodeResponse(DecisionsFixtures.documentedResponse)
        let reversed = DecisionsResponse(answers: response.answers.reversed(), usage: nil)
        for answer in response.answers {
            expect(
                reversed.answer(named: answer.name ?? "") == answer,
                "answer \(answer.name ?? "?") found by name in reversed order")
        }
        expect(response.answer(named: "missing") == nil, "unknown name answers nil")
    }

    /// Copy 的文本形态必须稳定钉住：英文与中文各一份基线。
    static func serializationIsStableInBothLanguages() {
        let response = decodeResponse(DecisionsFixtures.documentedResponse)
        let english = DecisionsResultText.serialize(
            response.answers, usage: response.usage, language: .english)
        let expectedEnglish = """
            is_negative: Yes (99%)
            category: quality (confidence 88%)
              quality 91% · logistics 1% · service 8% · other 0%
            severity: 中等 (score 1.0)
              轻微 6% · 中等 90% · 严重 4%
            needs_reply: refused
            Tokens: 520 in · 0 out
            """
        expect(english == expectedEnglish, "English serialization pinned, got:\n\(english)")

        let chinese = DecisionsResultText.serialize(
            response.answers, usage: response.usage, language: .chinese)
        let expectedChinese = """
            is_negative：是（99%）
            category：quality（置信度 88%）
              quality 91% · logistics 1% · service 8% · other 0%
            severity：中等（评分 1.0）
              轻微 6% · 中等 90% · 严重 4%
            needs_reply：拒答
            Token：输入 520 · 输出 0
            """
        expect(chinese == expectedChinese, "Chinese serialization pinned, got:\n\(chinese)")

        let noUsage = DecisionsResultText.serialize(response.answers, usage: nil, language: .english)
        expect(!noUsage.contains("Tokens"), "no usage, no tokens footer")
    }

    /// 问题集经 JSON 往返后必须逐字段还原（它以 blob 形式存在 UserDefaults）。
    static func questionSetsSurviveARoundTrip() {
        let original = DecisionsQuestionSet.standard
        let data = encodeSet(original)
        let restored = decodeSet(data)
        expect(restored == original, "round trip preserves every question")
    }

    /// 文档的「完整地址」行带着 /decisions；把它粘进端点字段不能拼出双重路径。
    static func pastedFullAddressesNormalizeToTheBase() {
        let normalize = DecisionsRouting.normalizeBase
        expect(
            normalize("https://ai-platform.bestfulfill-inc.com/v1")
                == "https://ai-platform.bestfulfill-inc.com/v1",
            "a bare base URL stays as it is")
        expect(
            normalize("https://ai-platform.bestfulfill-inc.com/v1/decisions")
                == "https://ai-platform.bestfulfill-inc.com/v1",
            "the documented full address strips its /decisions")
        expect(
            normalize("https://ai-platform.bestfulfill-inc.com/v1/decisions/")
                == "https://ai-platform.bestfulfill-inc.com/v1",
            "a trailing slash changes nothing")
        expect(
            normalize("https://ai-platform.bestfulfill-inc.com/v1/decisions/decisions")
                == "https://ai-platform.bestfulfill-inc.com/v1",
            "a doubled paste strips both")
        expect(
            normalize("https://ai-platform.bestfulfill-inc.com/v1/models")
                == "https://ai-platform.bestfulfill-inc.com/v1",
            "the models check URL strips too")
        expect(
            normalize("  https://ai-platform.bestfulfill-inc.com/v1  ")
                == "https://ai-platform.bestfulfill-inc.com/v1",
            "surrounding whitespace is trimmed")
        expect(
            normalize("https://gateway.internal:8443/decisions")
                == "https://gateway.internal:8443",
            "a bare host with the suffix still strips")
    }

    /// 模型即路由：只有 `-decisions` 结尾的模型走判定端点。
    static func decisionsModelsRouteThemselves() {
        expect(
            DecisionsRouting.isDecisionsModel("openai/gpt-6-luna-decisions"),
            "the documented model is a decisions model")
        expect(
            DecisionsRouting.isDecisionsModel("gpt-6-luna-decisions"),
            "the suffix alone decides")
        expect(
            !DecisionsRouting.isDecisionsModel("gpt-6-luna"),
            "the plain chat model is not")
        expect(
            !DecisionsRouting.isDecisionsModel("gpt-6-luna-decisions-chat"),
            "the suffix must be the end of the id")
    }
}

/// Fixture 解码：格式错误属于测试自身的缺陷，直接失败最响亮。
private func decodeResponse(_ json: String) -> DecisionsResponse {
    do {
        return try JSONDecoder().decode(DecisionsResponse.self, from: Data(json.utf8))
    } catch {
        fatalError("fixture is not a DecisionsResponse: \(error)")
    }
}

private func encodeSet(_ set: DecisionsQuestionSet) -> Data {
    do {
        return try JSONEncoder().encode(set)
    } catch {
        fatalError("question set failed to encode: \(error)")
    }
}

private func decodeSet(_ data: Data) -> DecisionsQuestionSet {
    do {
        return try JSONDecoder().decode(DecisionsQuestionSet.self, from: data)
    } catch {
        fatalError("question set failed to decode: \(error)")
    }
}

private extension DecisionsQuestionSet {
    /// 问题名列表，测试辅助。
    func answerNames() -> [String] {
        questions.map(\.name)
    }
}

/// 文档 §5.1 的典型响应，逐字段照抄。
enum DecisionsFixtures {
    static let documentedResponse = #"""
    {
      "answers": [
        {
          "type": "predicate",
          "name": "is_negative",
          "probability": 0.99
        },
        {
          "type": "choice",
          "name": "category",
          "choice": "quality",
          "probabilities": [
            {"value": "quality", "probability": 0.91},
            {"value": "logistics", "probability": 0.01},
            {"value": "service", "probability": 0.08},
            {"value": "other", "probability": 0.0}
          ],
          "confidence": 0.88
        },
        {
          "type": "score",
          "name": "severity",
          "score": 1.0,
          "probabilities": [
            {"value": 0, "label": "轻微", "probability": 0.06},
            {"value": 1, "label": "中等", "probability": 0.9},
            {"value": 2, "label": "严重", "probability": 0.04}
          ],
          "confidence": 0.87
        },
        {
          "type": "refusal",
          "name": "needs_reply"
        }
      ],
      "usage": {
        "input_tokens": 520,
        "output_tokens": 0,
        "total_tokens": 520
      }
    }
    """#
}
