// 文件职责：绘制定时刷新类扩展命令的行尾状态图标（运行中、已关闭、失败三种）。
// 分层：UI；只根据传入状态渲染，不持有刷新逻辑。
import SwiftUI

/// 定时扩展命令在启动器行上显示的指示图标。共享行仅内嵌它，不持有它的任何状态。
struct ExtensionRefreshIndicator: View {
    let state: ExtensionRefreshState

    /// 按刷新状态渲染对应图标与提示文案。
    var body: some View {
        switch state {
        case .active:
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(.secondary)
                .help("Refreshes in the background")
        case .idle:
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .foregroundStyle(.tertiary)
                .help("Background refresh is off — enable it from Actions")
        case .failed(let message):
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .help(message)
        }
    }
}
