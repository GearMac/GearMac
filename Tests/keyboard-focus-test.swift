// 文件职责：验证 KeyboardFocusRefusing 标记能使被标记视图及其子视图拒绝键盘焦点，而未标记视图不受影响。
// 分层：测试 harness；仅依赖 AppKit 视图层级，不涉及真实面板。
import AppKit

/// 面板的键盘输入属于搜索框，预览的播放控件绝不能夺取它。
@main
@MainActor
struct KeyboardFocusTests {
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

    /// 模拟播放器界面：该标记的含义是「这里面的任何东西都不接受焦点」。
    final class MarkedView: NSView, KeyboardFocusRefusing {}

    /// harness 入口：运行全部焦点拒绝相关用例。
    static func main() {
        theMarkedViewRefuses()
        aDescendantOfTheMarkRefuses()
        everythingElseAccepts()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func theMarkedViewRefuses() {
        expect(MarkedView().refusesKeyboardFocus, "the marked view itself refuses focus")
    }

    /// 真正的问题控件是 `AVDesktopButton`，一个由播放控件持有的私有控件。
    static func aDescendantOfTheMarkRefuses() {
        let marked = MarkedView()
        let button = NSButton()
        let bar = NSView()
        bar.addSubview(button)
        marked.addSubview(bar)
        expect(button.refusesKeyboardFocus, "a control nested under the mark refuses focus too")
    }

    static func everythingElseAccepts() {
        let root = NSView()
        let field = NSTextField()
        let marked = MarkedView()
        root.addSubview(field)
        root.addSubview(marked)
        expect(!field.refusesKeyboardFocus, "a sibling of the mark still takes focus")
        expect(!root.refusesKeyboardFocus, "an ancestor of the mark still takes focus")
        expect(!NSView().refusesKeyboardFocus, "an unparented view takes focus")
    }
}
