// 文件职责：摄像头面板使用的主/次操作按钮组件（含快捷键提示与样式映射）。
// 分层：UI（SwiftUI）；样式语言与对话框底部按钮保持一致。
import SwiftUI

/// 摄像头的操作按钮，沿用对话框底部按钮一致的视觉语言。
struct CameraButton: View {
    /// 次要也同时表达「关闭」：镜像开关用变暗表示，而不是新增一种按钮样式。
    enum Emphasis {
        case primary
        case secondary
    }

    let title: String
    var keyCap: String?
    var emphasis: Emphasis = .primary
    let onActivate: () -> Void

    var body: some View {
        Button(title, action: onActivate)
            .buttonStyle(.modalAction(role, fillsWidth: false))
            .tooltip(keyCap: keyCap)
    }

    /// 主按钮映射为 .primary，次要按钮映射为 .cancel。
    private var role: ModalActionButtonStyle.Role {
        emphasis == .primary ? .primary : .cancel
    }
}
