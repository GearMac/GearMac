// 文件职责：布局编辑器左栏的预览区：按比例绘制单个显示器的画布，以及画布本身的条目矩形绘制。
// 分层：UI（SwiftUI 绘图）；几何全部来自 WindowLayoutGeometry / WindowLayoutDraft，不在此重新推导。
import AppKit
import SwiftUI

/// 编辑器左栏：按比例绘制单个显示器、叠加其上的条目矩形，以及显示器页签。
struct WindowLayoutPreview: View {
    let draft: WindowLayoutDraft
    /// 由面板一次性解析：每次渲染都做 AX 读取会让每次按键都多一次跨进程往返。
    let screens: [WindowLayoutScreen]
    let gap: CGFloat

    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            // 尽量占满：画布会自行留黑边居中，因此这里多出的空间用于绘制而非外边距。
            WindowLayoutPreviewCanvas(draft: draft, screen: selectedScreen, gap: gap)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 放在说明文字旁边而非盖在画布上：页签绝不应遮挡窗口矩形。
            HStack(spacing: Theme.Spacing.md) {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                WindowLayoutDisplayTabs(draft: draft, displays: tabs)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 当前连接的显示器页签。
    private var tabs: [WindowLayoutDisplay] {
        draft.tabs(connected: screens.map(\.display))
    }

    /// 当前选中页签的屏幕几何；该显示器未连接时为 nil。
    private var selectedScreen: WindowLayoutScreen? {
        guard let uuid = draft.selectedDisplayUUID else { return nil }
        return screens.first { $0.display.uuid == uuid }
    }

    /// 画布下方的说明：显示器名与尺寸（点）；未连接时给出提示。
    private var caption: String {
        guard let uuid = draft.selectedDisplayUUID,
            let display = tabs.first(where: { $0.uuid == uuid })
        else { return settings.text(WindowKey.previewNoDisplay) }
        guard let screen = selectedScreen else {
            return String(format: settings.text(WindowKey.previewCaptionNotConnected), display.name)
        }
        // 用点而非像素：本功能不涉及 `backingScaleFactor`。
        let size = screen.screen.frame.size
        return "\(display.name) · \(Int(size.width)) × \(Int(size.height))"
    }
}

/// 按比例绘制一个显示器，并在其上为每个条目画一个圆角矩形。只绘制，不做决策。
struct WindowLayoutPreviewCanvas: View {
    let draft: WindowLayoutDraft
    let screen: WindowLayoutScreen?
    let gap: CGFloat

    @Environment(AppIndex.self) private var appIndex
    @Environment(AppSettings.self) private var settings

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let screen {
                    // 底板即显示器本身，保持其自身宽高比。
                    let ground = ground(in: proxy.size, display: screen.screen.visibleFrame)
                    plate
                        .frame(width: ground.width, height: ground.height)
                        .position(x: ground.midX, y: ground.midY)
                    ForEach(placements(on: screen), id: \.entry.id) { placed in
                        entryRect(placed, ground: ground, display: screen.screen.visibleFrame)
                    }
                } else {
                    plate
                    Text(settings.text(WindowKey.previewDisplayNotConnected))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    /// 画布底板：一块填充了预览底色的圆角矩形。
    private var plate: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .fill(Theme.Colors.layoutPreviewGround)
    }

    /// 已定位的条目：条目本身加它在屏幕坐标系中的矩形。
    private struct Placed {
        let entry: WindowLayoutEntry
        let frame: CGRect
    }

    /// 所有矩形都来自运行器使用的同一个解析器，此处不重新推导几何。
    private func placements(on screen: WindowLayoutScreen) -> [Placed] {
        draft.entries(onDisplay: screen.display.uuid).compactMap { entry in
            WindowLayoutGeometry.resolve(entry, on: screen.screen, gap: gap)
                .map { Placed(entry: entry, frame: $0) }
        }
    }

    /// 求包含而非填充：把 16:10 显示器拉伸进 16:9 画框会让内部所有矩形画错。
    private func ground(in box: CGSize, display: CGRect) -> CGRect {
        guard display.width > 0, display.height > 0 else { return .zero }
        let scale = min(box.width / display.width, box.height / display.height)
        let size = CGSize(width: display.width * scale, height: display.height * scale)
        return CGRect(
            x: (box.width - size.width) / 2, y: (box.height - size.height) / 2,
            width: size.width, height: size.height)
    }

    /// 把屏幕坐标系中的条目矩形映射到画布坐标系并绘制（含选中态与图标）。
    @ViewBuilder
    private func entryRect(_ placed: Placed, ground: CGRect, display: CGRect) -> some View {
        let isSelected = placed.entry.id == draft.selectedEntryID
        let scale = display.width > 0 ? ground.width / display.width : 0
        let rect = CGRect(
            x: ground.minX + (placed.frame.minX - display.minX) * scale,
            y: ground.minY + (placed.frame.minY - display.minY) * scale,
            width: placed.frame.width * scale, height: placed.frame.height * scale)
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous)

        shape
            .fill(
                isSelected
                    ? Theme.Colors.layoutPreviewWindowSelected : Theme.Colors.layoutPreviewWindow
            )
            .overlay(shape.stroke(isSelected ? Color.accentColor : Theme.Colors.border))
            .overlay(icon(for: placed.entry.bundleID))
            .frame(width: max(1, rect.width), height: max(1, rect.height))
            .position(x: rect.midX, y: rect.midY)
            // 最后绘制，因为一份布局可能合理地叠放两个窗口。
            .zIndex(isSelected ? 1 : 0)
    }

    /// 走索引缓存：每个矩形都调 `urlForApplication` 会让每次按键都触发磁盘访问。
    private func icon(for bundleID: String) -> some View {
        Image(nsImage: AppPresentation.resolve(bundleID: bundleID, in: appIndex).icon)
            .resizable()
            .frame(width: Theme.Size.layoutPreviewIcon, height: Theme.Size.layoutPreviewIcon)
    }

    /// 供 VoiceOver 使用的描述：显示器名与窗口数量；未连接时说明情况。
    private var accessibilityDescription: String {
        guard let screen else {
            return settings.text(WindowKey.previewNotConnectedLabel)
        }
        let count = draft.entries(onDisplay: screen.display.uuid).count
        let windows =
            count == 1
            ? settings.text(WindowKey.summaryWindowOne)
            : String(format: settings.text(WindowKey.summaryWindowMany), count)
        return String(
            format: settings.text(WindowKey.previewDescription), screen.display.name, windows)
    }
}
