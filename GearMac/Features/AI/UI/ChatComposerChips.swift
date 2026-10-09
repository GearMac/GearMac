// 文件职责：输入框上的胶囊组件：MCP `@server` 胶囊、已暂存附件胶囊及其缩略图。
// 分层：UI（SwiftUI 视图）；纯展示与回调，宽度计算供输入框宽度预留使用，不持有业务状态。
import AppKit
import SwiftUI

/// MCP `@server` 胶囊：只显示图标，因为它确认的 `@句柄` 已经在文本里了。
struct ComposerChip: View {
    @Environment(\.metrics) private var metrics
    let symbol: String
    let label: String

    /// 关键逻辑：该宽度是 `searchFieldWidth(for:)` 从输入框宽度中扣除的条带宽度的一部分。
    static func width(_ metrics: InterfaceMetrics) -> CGFloat {
        metrics.size.chatAttachmentGlyph + metrics.spacing.sm * 2
    }

    var body: some View {
        Image(systemName: symbol)
            .font(metrics.typography.chip)
            .symbolRenderingMode(.hierarchical)
            .frame(width: metrics.size.chatAttachmentGlyph)
            .foregroundStyle(Theme.Colors.textSecondary)
            .padding(.horizontal, metrics.spacing.sm)
            .padding(.vertical, metrics.spacing.xxs)
            .background(Capsule().fill(Theme.Colors.controlSurface))
            .tooltip("Offers only \(label)'s tools", edge: .bottom)
            .accessibilityLabel("Addressed to \(label)")
    }
}

/// 窗口输入框里已暂存的文件：图片展示自身，文档展示文件名，两者都带一个 ✕。
struct AttachmentChip: View {
    @Environment(\.metrics) private var metrics
    let attachment: ChatAttachment
    let onRemove: () -> Void

    @State private var hovered = false

    /// 超过这个长度就对文件名做中间截断，让一排胶囊仍能一眼读懂。
    private static let nameLimit = 16

    /// 每种类型都带文字标签：✕ 旁边只有一个裸缩略图会像两个孤立的标记，而不像一个胶囊。
    private static func shortened(_ name: String) -> String {
        guard name.count > nameLimit else { return name }
        return "\(name.prefix(nameLimit - 7))…\(name.suffix(6))"
    }

    var body: some View {
        HStack(spacing: metrics.spacing.sm) {
            leading
            Text(Self.shortened(attachment.name))
                .font(metrics.typography.chip)
                .lineLimit(1)
                .foregroundStyle(Theme.Colors.textSecondary)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(
                        width: metrics.size.chatAttachmentRemove,
                        height: metrics.size.chatAttachmentRemove
                    )
                    .foregroundStyle(hovered ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove \(attachment.name)")
        }
        // 内边距小于内部间距，让缩略图看起来是填满整个胶囊。
        .padding(.horizontal, metrics.size.chatAttachmentInset)
        .padding(.vertical, metrics.size.chatAttachmentInset)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.attachmentChip, style: .continuous)
                .fill(Theme.Colors.controlSurface)
        )
        .onHover { hovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Attached \(attachment.name)")
    }

    /// 胶囊的前导内容：图片显示缩略图，PDF/文本显示对应类型的图标。
    @ViewBuilder private var leading: some View {
        switch attachment.kind {
        case .image:
            ComposerThumbnail(data: attachment.preview, id: attachment.id)
        case .pdf, .text:
            Image(systemName: attachment.glyph)
                .font(metrics.typography.chip)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(
                    width: metrics.size.chatAttachmentThumb,
                    height: metrics.size.chatAttachmentThumb)
        }
    }
}

/// 每个附件只解码一次：`ForEach` 以它的 id 为键，因此每敲一次键的重渲染都会复用它。
private struct ComposerThumbnail: View {
    @Environment(\.metrics) private var metrics
    let data: Data?
    let id: UUID

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(metrics.typography.chip)
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .frame(width: metrics.size.chatAttachmentThumb, height: metrics.size.chatAttachmentThumb)
        .clipShape(RoundedRectangle(cornerRadius: metrics.radius.thumbnail, style: .continuous))
        .task(id: id) { image = data.flatMap(NSImage.init(data:)) }
    }
}
