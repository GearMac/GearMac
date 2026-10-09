// 文件职责：Dictation 文本格式化与模型元数据的独立测试，校验大小写/空白/标点适配及每个引擎的安装信息。
// 分层：测试 harness；直接调用真实的 DictationTextFormatter 与 DictationModel，不启动推理。

import Foundation

/// 独立可执行测试入口：先跑文本格式化用例，再校验模型元数据自洽。
@main
struct DictationTest {
    static func main() {
        /// 断言两个字符串相等，否则打印差异并退出。
        func check(_ actual: String, _ expected: String) {
            guard actual == expected else {
                print("Expected \(expected.debugDescription), got \(actual.debugDescription)")
                exit(1)
            }
        }

        // 文本格式化：开头空白、句首大写、前后标点与嫩号等上下文适配。
        typealias Context = DictationTextFormatter.Context
        check(DictationTextFormatter.format("  Hello. \n", context: nil), "Hello.")
        check(DictationTextFormatter.format("hello", context: Context(before: "", after: "")), "Hello")
        check(DictationTextFormatter.format("World", context: Context(before: "Hello", after: "")), " world")
        check(DictationTextFormatter.format("world", context: Context(before: "Hello.", after: "")), " World")
        check(DictationTextFormatter.format("hello", context: Context(before: "Wait. ", after: "")), "Hello")
        check(
            DictationTextFormatter.format("hello", context: Context(before: "Wait\n  ", after: "")), "Hello")
        check(
            DictationTextFormatter.format("World", context: Context(before: "Hello ", after: "again")),
            "world ")
        check(DictationTextFormatter.format("hello", context: Context(before: "(", after: ")")), "hello")
        check(
            DictationTextFormatter.format("application", context: Context(before: "l’", after: "")),
            "application")
        check(
            DictationTextFormatter.format(
                "GearMac", context: Context(before: "Use", after: "again"),
                adaptCapitalization: false), " GearMac ")
        check(
            DictationTextFormatter.format(
                "world", context: Context(before: "Hello.", after: ""),
                adaptCapitalization: false), " world")
        check(
            DictationTextFormatter.format(
                "hello", context: Context(before: "", after: ""),
                adaptCapitalization: false), "hello")
        check(
            DictationTextFormatter.format(
                "World.", context: Context(before: "Hello ", after: ")"),
                adaptCapitalization: false), "World.")
        // 只截取邻近上下文时，替换范围两侧仍需各留一个空格。
        let document = "prefix. Text to replace suffix"
        check(
            DictationTextFormatter.format(
                "world",
                context: Context(
                    before: document.prefix(7), after: document.suffix(6))), " World ")
        // 模型元数据：目录名、显示名与空闲释放选项的取值固定。
        check(DictationModel.redux.folderName, "parakeet-redux")
        check(DictationModel.ultra.folderName, "parakeet-ultra")
        check(DictationModel.redux.title, "Parakeet · Redux")
        check(DictationModel.ultra.title, "Parakeet · Ultra")
        check(DictationIdleRelease.allCases.map(\.rawValue).description, "[0, 1, 2, 5, 10, 15, 20, 30, 60]")
        check(DictationIdleRelease.never.title(.english), "Never")
        check(DictationIdleRelease.oneHour.title(.english), "1 hour")
        check(DictationModel.qwenSmall.folderName, "qwen-0.6b")
        check(DictationModel.qwenLarge.folderName, "qwen-1.7b")
        for family in DictationModel.Family.allCases {
            guard DictationModel.allCases.contains(where: { $0.family == family }) else {
                fatalError("Every engine should expose at least one model")
            }
        }
        // 每个模型都必须暴露完整可下载文件、40 位 revision 与自洽的 Parakeet 配置。
        for model in DictationModel.allCases {
            guard !model.components.isEmpty, model.revision.count == 40,
                model.requiredFiles.isSuperset(of: model.components)
            else {
                fatalError("Model installation metadata is incomplete")
            }
            if let configuration = model.parakeetConfiguration {
                guard model.family == .parakeet, configuration.blankToken == 8192,
                    configuration.encoderUsesGPU == (model == .redux),
                    model.components.contains(configuration.joint + ".mlmodelc")
                else {
                    fatalError("Parakeet download and inference disagree")
                }
            } else if !model.isQwen {
                fatalError("Missing Parakeet decoding configuration")
            }
        }
        print("Dictation text formatting passed")
    }
}
