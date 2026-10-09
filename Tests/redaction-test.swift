// 文件职责：RedactedPlaceholder（脱敏占位符）的独立测试 harness，验证同一取值始终得到同一脱敏串、结构字符位置不变、字符集避开易混字形。
// 分层：测试 harness；纯函数断言，不读写文件。
import Foundation

/// 脱敏后的伪装必须稳定、保持地址形态，且不向细看的人泄露任何信息。
@main
struct RedactionTest {
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

        let email = "ashish.kumar@example.com"
        let redacted = RedactedPlaceholder.forValue(email)

        check(
            "the same value always wears the same disguise",
            redacted == RedactedPlaceholder.forValue(email))
        check(
            "a different value gets a different one",
            RedactedPlaceholder.forValue("someone.else@example.com") != redacted)
        check("length is preserved, so the row does not reflow", redacted.count == email.count)

        func atOffset(_ text: String) -> Int? {
            text.firstIndex(of: "@").map { text.distance(from: text.startIndex, to: $0) }
        }
        check("the @ stays put", atOffset(redacted) == atOffset(email))
        check(
            "every dot keeps its position",
            zip(redacted, email).allSatisfy { left, right in (left == ".") == (right == ".") })
        check(
            "hyphens and underscores pass through",
            RedactedPlaceholder.forValue("a-b_c@d.e").filter { "-_@.".contains($0) } == "-_@.")

        let structural = Set("@._-")
        // 不是“每个字符都不同”：刻意避开真实字形反而会暴露它不是原值。
        let content = zip(redacted, email).filter { !structural.contains($0.1) }
        let moved = content.filter { $0.0 != $0.1 }.count
        check("the disguise is not the value", redacted != email)
        check(
            "the overwhelming majority of characters moved",
            Double(moved) / Double(content.count) > 0.8)
        check(
            "structural characters are the only ones guaranteed to match",
            zip(redacted, email).allSatisfy { left, right in
                structural.contains(right) ? left == right : true
            })

        let ambiguous = Set("ilo01")
        check(
            "the alphabet avoids look-alike glyphs",
            redacted.filter { !structural.contains($0) }.allSatisfy { !ambiguous.contains($0) })

        check("an empty value produces an empty disguise", RedactedPlaceholder.forValue("").isEmpty)
        check(
            "a value that is only structure is returned unchanged",
            RedactedPlaceholder.forValue("@.") == "@.")

        // 若伪装只重复同一个字符，会一眼看出是假的。
        let letters = redacted.filter { !structural.contains($0) }
        check("the scramble is not a single repeated character", Set(letters).count > 1)

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
