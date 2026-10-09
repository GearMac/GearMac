// 文件职责：无结果时的占位视图，居中展示放大镜图标与一段提示文案。
// 分层：UI（SwiftUI）；纯展示，不含业务状态。
import SwiftUI

/// 空结果占位：图标加大字提示，铺满可用空间并居中。
struct EmptyResults: View {
    let text: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.largeTitle)
                .symbolRenderingMode(.hierarchical).foregroundStyle(.tertiary)
            Text(text).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
