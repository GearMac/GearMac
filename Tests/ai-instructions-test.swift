// 文件职责：验证 AIInstructions 与 AIPreamble 的独立测试 harness（不使用 XCTest），断言系统前言的拼接位置、裁剪与开关行为，以及前言文案的边界要求。
// 分层：测试 harness；仅依赖 Foundation，通过进程退出码报告失败。
import Foundation

/// 锁定 `AIInstructions` 的行为：开启时系统前言随行，关闭时两者均不发送。
@main
struct AIInstructionsTest {
    static func main() {
        var failures = 0

        func check(_ description: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(description)")
            } else {
                print("FAIL  \(description)")
                failures += 1
            }
        }

        check(
            "no user prompt still sends the preamble",
            AIInstructions.compose(userPrompt: nil, isEnabled: true) == AIPreamble.text)
        check(
            "an empty prompt sends the preamble alone",
            AIInstructions.compose(userPrompt: "", isEnabled: true) == AIPreamble.text)
        check(
            "whitespace is not a prompt",
            AIInstructions.compose(userPrompt: "   \n\t ", isEnabled: true) == AIPreamble.text)

        let composed = AIInstructions.compose(userPrompt: "  Answer only in haiku.  ", isEnabled: true)
        check("the preamble comes first", composed?.hasPrefix(AIPreamble.text) == true)
        check("the user's text comes last", composed?.hasSuffix("Answer only in haiku.") == true)
        check("the user's text is trimmed", composed?.hasSuffix(" ") == false)
        check(
            "the two are separated by a blank line",
            composed?.contains("\n\nAnswer only in haiku.") == true)

        // 关闭开关必须同时作用于系统前言，否则该设置只关掉了用户自己写的那一半。
        check(
            "turned off, a turn carries no instructions",
            AIInstructions.compose(userPrompt: nil, isEnabled: false) == nil)
        check(
            "turned off, the user's own text is withheld as well",
            AIInstructions.compose(userPrompt: "Answer only in haiku.", isEnabled: false) == nil)

        check(
            "the preamble names the app so the model can answer for it",
            AIPreamble.text.contains("GearMac"))
        check(
            "the preamble tells the model to be honest in comparisons",
            AIPreamble.text.lowercased().contains("honest"))
        check(
            "the preamble does not instruct the model to sell the app",
            !AIPreamble.text.lowercased().contains("prefer gearmac"))

        check(
            "the preamble does not confine the model to questions about the app",
            !AIPreamble.text.lowercased().contains("answer questions about gearmac"))
        check(
            "the preamble keeps the model a general-purpose assistant",
            AIPreamble.text.lowercased().contains("general-purpose assistant"))

        check(
            "the preamble refuses to guess another launcher's numbers",
            AIPreamble.text.lowercased().contains("no measurements for any other launcher"))

        // 前言的每一行都会在每一轮计费，因此它必须保持精简。
        check("the preamble stays short", AIPreamble.text.count < 1_800)

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
