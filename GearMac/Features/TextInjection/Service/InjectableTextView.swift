// 文件职责：定义 `InjectableTextView` 协议——声明某个 NSTextView 可接受由 GearMac 在同进程内直接写入的文本。
// 分层：Service（TextInjection）；选择性加入，仅由自家编辑器视图采纳。
import AppKit

/// 选择性加入：采纳该协议的视图接受由 GearMac 在同进程内直接写入的注入文本。
protocol InjectableTextView where Self: NSTextView {}

extension InjectableTextView {
    /// 当前选中的文本；进程内注入时用作替换目标。
    var injectableSelection: String {
        (string as NSString).substring(with: selectedRange())
    }
}
