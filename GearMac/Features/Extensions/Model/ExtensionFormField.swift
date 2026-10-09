// 文件职责：把 `Form.*` 节点类型归类为表单键盘导航所需的字段类别（可聚焦类型与惰性类型）。
// 分层：Model；纯枚举与映射逻辑，不 import AppKit/SwiftUI。
/// `Form.*` 节点在表单键盘导航语义下的归类。
enum ExtensionFormField: Equatable {
    case text
    case textArea
    case checkbox
    case dropdown
    case tagPicker
    case datePicker
    case filePicker
    /// 分隔线、描述文本、附件等——会被绘制，但永远不会成为焦点。
    case inert

    /// 根据 `Form.*` 类型字符串映射到对应的字段类别；未知类型一律归为 `inert`。
    init(type: String) {
        switch type {
        case "Form.TextField", "Form.PasswordField": self = .text
        case "Form.TextArea": self = .textArea
        case "Form.Checkbox": self = .checkbox
        case "Form.Dropdown": self = .dropdown
        case "Form.TagPicker": self = .tagPicker
        case "Form.DatePicker": self = .datePicker
        case "Form.FilePicker": self = .filePicker
        default: self = .inert
        }
    }

    /// 该字段是否能获得键盘焦点。
    var isFocusable: Bool { self != .inert }

    /// 文本区用 ↑/↓ 编辑，因此表单把这两个键交给它，离开则靠 Tab。
    var ownsVerticalKeys: Bool { self == .textArea }
}
