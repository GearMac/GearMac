// 文件职责：定义界面度量（间距、圆角、尺寸、字体）的两层令牌体系：`Theme` 为基准值，`InterfaceMetrics` 按用户 Interface Size 缩放。
// 分层：UI（DesignSystem）；度量值均从 `Theme` 派生并按比例取整，不直接硬编码具体数值。
import SwiftUI

/// 按用户所设 Interface Size 缩放后的 `Theme` 调色板几何值；`.standard` 即 `Theme` 原值。
struct InterfaceMetrics: Equatable, Sendable {
    static let standard = InterfaceMetrics(scale: 1)

    let scale: CGFloat

    var spacing: Spacing { Spacing(scale: scale) }
    var radius: Radius { Radius(scale: scale) }
    var size: Size { Size(scale: scale) }
    var typography: Typography { Typography(scale: scale) }

    /// 用于某个界面自行微调、而 `Theme` 未定义对应 token 的长度。
    func scaled(_ value: CGFloat) -> CGFloat { scaledPoints(value, scale) }

    /// 缩放后的间距 token 集合。
    struct Spacing: Equatable, Sendable {
        let scale: CGFloat

        var xxs: CGFloat { scaledPoints(Theme.Spacing.xxs, scale) }
        var xs: CGFloat { scaledPoints(Theme.Spacing.xs, scale) }
        var sm: CGFloat { scaledPoints(Theme.Spacing.sm, scale) }
        var md: CGFloat { scaledPoints(Theme.Spacing.md, scale) }
        var lg: CGFloat { scaledPoints(Theme.Spacing.lg, scale) }
        var xl: CGFloat { scaledPoints(Theme.Spacing.xl, scale) }
        var dialogInset: CGFloat { scaledPoints(Theme.Spacing.dialogInset, scale) }
        var xxl: CGFloat { scaledPoints(Theme.Spacing.xxl, scale) }
        var xxxl: CGFloat { scaledPoints(Theme.Spacing.xxxl, scale) }
        var sectionHeaderBottom: CGFloat { scaledPoints(Theme.Spacing.sectionHeaderBottom, scale) }
        var sectionSpacing: CGFloat { scaledPoints(Theme.Spacing.sectionSpacing, scale) }
        var emojiSectionSpacing: CGFloat { scaledPoints(Theme.Spacing.emojiSectionSpacing, scale) }
        var chatTranscriptBottom: CGFloat { scaledPoints(Theme.Spacing.chatTranscriptBottom, scale) }
        var chatFollowTailSlack: CGFloat { scaledPoints(Theme.Spacing.chatFollowTailSlack, scale) }
        var chatLine: CGFloat { scaledPoints(Theme.Spacing.chatLine, scale) }
    }

    /// 缩放后的圆角 token 集合。
    struct Radius: Equatable, Sendable {
        let scale: CGFloat

        var panel: CGFloat { scaledPoints(Theme.Radius.panel, scale) }
        var row: CGFloat { scaledPoints(Theme.Radius.row, scale) }
        var emojiCell: CGFloat { scaledPoints(Theme.Radius.emojiCell, scale) }
        var menu: CGFloat { scaledPoints(Theme.Radius.menu, scale) }
        var menuRow: CGFloat { scaledPoints(Theme.Radius.menuRow, scale) }
        var barControl: CGFloat { scaledPoints(Theme.Radius.barControl, scale) }
        var menuPanel: CGFloat { scaledPoints(Theme.Radius.menuPanel, scale) }
        var dialogSymbol: CGFloat { scaledPoints(Theme.Radius.dialogSymbol, scale) }
        var dialog: CGFloat { scaledPoints(Theme.Radius.dialog, scale) }
        var thumbnail: CGFloat { scaledPoints(Theme.Radius.thumbnail, scale) }
        var glyph: CGFloat { scaledPoints(Theme.Radius.glyph, scale) }
        var attachmentChip: CGFloat { scaledPoints(Theme.Radius.attachmentChip, scale) }
        var card: CGFloat { scaledPoints(Theme.Radius.card, scale) }
        var keyCap: CGFloat { scaledPoints(Theme.Radius.keyCap, scale) }
        var tooltip: CGFloat { scaledPoints(Theme.Radius.tooltip, scale) }
    }

    /// 缩放后的尺寸 token 集合。
    struct Size: Equatable, Sendable {
        let scale: CGFloat

        var panelWidth: CGFloat { scaledPoints(Theme.Size.panelWidth, scale) }
        var panelHeight: CGFloat { scaledPoints(Theme.Size.panelHeight, scale) }
        var headerHeight: CGFloat { scaledPoints(Theme.Size.headerHeight, scale) }
        var headerIconSlot: CGFloat { scaledPoints(Theme.Size.headerIconSlot, scale) }
        var searchFieldMinWidth: CGFloat { scaledPoints(Theme.Size.searchFieldMinWidth, scale) }
        var headerPadding: CGFloat { scaledPoints(Theme.Size.headerPadding, scale) }
        /// 由其他值推导而非直接缩放：紧凑栏高度必须正好是头部高度加上下对称留白。
        var compactHeight: CGFloat { headerHeight + headerPadding * 2 }
        var bottomBarHeight: CGFloat { scaledPoints(Theme.Size.bottomBarHeight, scale) }
        var barButtonHeight: CGFloat { scaledPoints(Theme.Size.barButtonHeight, scale) }
        var rowIcon: CGFloat { scaledPoints(Theme.Size.rowIcon, scale) }
        var resultRowIcon: CGFloat { scaledPoints(Theme.Size.resultRowIcon, scale) }
        var colorDot: CGFloat { scaledPoints(Theme.Size.colorDot, scale) }
        var calendarBarWidth: CGFloat { scaledPoints(Theme.Size.calendarBarWidth, scale) }
        var calendarBarHeight: CGFloat { scaledPoints(Theme.Size.calendarBarHeight, scale) }
        var keyCap: CGFloat { scaledPoints(Theme.Size.keyCap, scale) }
        var compactKeyCap: CGFloat { scaledPoints(Theme.Size.compactKeyCap, scale) }
        var heroKeyCap: CGFloat { scaledPoints(Theme.Size.heroKeyCap, scale) }
        var menuButton: CGFloat { scaledPoints(Theme.Size.menuButton, scale) }
        var checkbox: CGFloat { scaledPoints(Theme.Size.checkbox, scale) }

        var menuWidth: CGFloat { scaledPoints(Theme.Size.menuWidth, scale) }
        var actionMenuWidth: CGFloat { scaledPoints(Theme.Size.actionMenuWidth, scale) }
        var clipboardFilterMenuWidth: CGFloat { scaledPoints(Theme.Size.clipboardFilterMenuWidth, scale) }
        var fileSearchFilterMenuWidth: CGFloat { scaledPoints(Theme.Size.fileSearchFilterMenuWidth, scale) }
        var emojiCategoryMenuWidth: CGFloat { scaledPoints(Theme.Size.emojiCategoryMenuWidth, scale) }
        var menuIcon: CGFloat { scaledPoints(Theme.Size.menuIcon, scale) }
        var menuBrandIcon: CGFloat { scaledPoints(Theme.Size.menuBrandIcon, scale) }
        var barBrandIcon: CGFloat { scaledPoints(Theme.Size.barBrandIcon, scale) }
        var menuRowSpacing: CGFloat { scaledPoints(Theme.Size.menuRowSpacing, scale) }
        var menuSectionHeader: CGFloat { scaledPoints(Theme.Size.menuSectionHeader, scale) }
        /// 与 `Theme` 中相同的推导方式，使行数上限在任何尺寸下都按整行计算。
        var menuRowHeight: CGFloat { menuIcon + Spacing(scale: scale).md * 2 }
        var menuRowsMaxHeight: CGFloat {
            (Theme.Size.menuVisibleRows * (menuRowHeight + menuRowSpacing)).rounded()
        }
        var clipboardListWidth: CGFloat { scaledPoints(Theme.Size.clipboardListWidth, scale) }
        var clipboardCard: CGSize {
            CGSize(
                width: scaledPoints(Theme.Size.clipboardCard.width, scale),
                height: scaledPoints(Theme.Size.clipboardCard.height, scale))
        }
        var clipboardCardIcon: CGFloat { scaledPoints(Theme.Size.clipboardCardIcon, scale) }
        var clipboardSearchEntry: CGFloat { scaledPoints(Theme.Size.clipboardSearchEntry, scale) }
        /// 与 `Theme` 相同的推导方式：由已缩放的条带高度累加，而非直接缩放结果。
        var clipboardBarHeight: CGFloat {
            barButtonHeight + clipboardCard.height + Spacing(scale: scale).xxs * 2
                + Spacing(scale: scale).xs * 2 + Spacing(scale: scale).xxl * 2
        }
        var emojiGridInset: CGFloat { scaledPoints(Theme.Size.emojiGridInset, scale) }
        var emojiCell: CGFloat { scaledPoints(Theme.Size.emojiCell, scale) }

        var markdownListMarker: CGFloat { scaledPoints(Theme.Size.markdownListMarker, scale) }
        var markdownQuoteBar: CGFloat { scaledPoints(Theme.Size.markdownQuoteBar, scale) }
        var chatMessageAction: CGFloat { scaledPoints(Theme.Size.chatMessageAction, scale) }
        var chatImageThumb: CGFloat { scaledPoints(Theme.Size.chatImageThumb, scale) }
        var chatAttachmentGlyph: CGFloat { scaledPoints(Theme.Size.chatAttachmentGlyph, scale) }
        var chatAttachmentThumb: CGFloat { scaledPoints(Theme.Size.chatAttachmentThumb, scale) }
        var chatAttachmentRemove: CGFloat { scaledPoints(Theme.Size.chatAttachmentRemove, scale) }
        var chatAttachmentInset: CGFloat { scaledPoints(Theme.Size.chatAttachmentInset, scale) }

        var quickActionPanel: CGFloat { scaledPoints(Theme.Size.quickActionPanel, scale) }
        var quickActionHeaderIcon: CGFloat { scaledPoints(Theme.Size.quickActionHeaderIcon, scale) }
        var quickActionScrollFade: CGFloat { scaledPoints(Theme.Size.quickActionScrollFade, scale) }
        var quickActionPanelBody: CGFloat { scaledPoints(Theme.Size.quickActionPanelBody, scale) }
        var quickActionPanelMinBody: CGFloat { scaledPoints(Theme.Size.quickActionPanelMinBody, scale) }

        var dialogCompactWidth: CGFloat { scaledPoints(Theme.Size.dialogCompactWidth, scale) }
        var dialogWidth: CGFloat { scaledPoints(Theme.Size.dialogWidth, scale) }
        var dialogButtonHeight: CGFloat {
            menuButton
                - scaledPoints(Theme.Size.menuButton - Theme.Size.dialogButtonHeight, scale)
        }
        var dialogSymbol: CGFloat { scaledPoints(Theme.Size.dialogSymbol, scale) }
        var dialogSymbolContainer: CGFloat {
            scaledPoints(Theme.Size.dialogSymbolContainer, scale)
        }
        var dialogIcon: CGFloat { scaledPoints(Theme.Size.dialogIcon, scale) }
        var hudMaxWidth: CGFloat { scaledPoints(Theme.Size.hudMaxWidth, scale) }
        var hudWidth: CGFloat { scaledPoints(Theme.Size.hudWidth, scale) }
        var hudHeight: CGFloat { scaledPoints(Theme.Size.hudHeight, scale) }
        var volumeTrackHeight: CGFloat { scaledPoints(Theme.Size.volumeTrackHeight, scale) }
        var volumeReadout: CGFloat { scaledPoints(Theme.Size.volumeReadout, scale) }
    }

    /// 缩放后的字体 token 集合；`NSFont` 是获取文本样式字号与字面的唯一公开来源。
    struct Typography: Sendable {
        let scale: CGFloat

        var searchFieldSize: CGFloat { scaledPoints(Theme.Typography.searchFieldSize, scale) }
        var searchField: Font {
            scale == 1
                ? Theme.Typography.searchField
                : .system(size: searchFieldSize, weight: .regular)
        }
        /// 标为 `@MainActor` 只是因为 `Theme` 中对应的属性如此，并非解析字体需要主线程。
        @MainActor var searchFieldNSFont: NSFont {
            scale == 1
                ? Theme.Typography.searchFieldNSFont
                : NSFont.systemFont(ofSize: searchFieldSize, weight: .regular)
        }
        var headerIcon: Font {
            scale == 1
                ? Theme.Typography.headerIcon
                : .system(size: scaledPoints(18, scale), weight: .medium)
        }

        var rowTitle: Font { font(Theme.Typography.rowTitle, .body) }
        var rowTrailing: Font { font(Theme.Typography.rowTrailing, .callout) }
        var sectionHeader: Font { font(Theme.Typography.sectionHeader, .subheadline, .medium) }
        var panelTitle: Font { font(Theme.Typography.panelTitle, .headline) }
        var calcResult: Font { font(Theme.Typography.calcResult, .title1) }
        var keyCap: Font { font(Theme.Typography.keyCap, .caption1) }
        var compactKeyCap: Font { font(Theme.Typography.compactKeyCap, .caption2) }
        var heroKeyCap: Font { font(Theme.Typography.heroKeyCap, .body) }
        var markdownHeading1: Font { font(Theme.Typography.markdownHeading1, .title2, .semibold) }
        var markdownHeading2: Font { font(Theme.Typography.markdownHeading2, .title3, .semibold) }
        var markdownHeading3: Font { font(Theme.Typography.markdownHeading3, .headline) }
        var code: Font {
            scale == 1
                ? Theme.Typography.code
                : .system(size: nsFont(.callout).pointSize, design: .monospaced)
        }
        var inlineCode: Font { font(Theme.Typography.inlineCode, .body).monospaced() }
        var bar: Font { font(Theme.Typography.bar, .callout, .medium) }
        var chip: Font { font(Theme.Typography.chip, .callout) }
        @MainActor var chipNSFont: NSFont { scale == 1 ? Theme.Typography.chipNSFont : nsFont(.callout) }
        var disclosure: Font { font(Theme.Typography.disclosure, .caption1, .semibold) }
        var cardText: Font { font(Theme.Typography.cardText, .footnote) }
        var cardMeta: Font { font(Theme.Typography.cardMeta, .caption2) }
        var menuRow: Font { font(Theme.Typography.menuRow, .body) }
        var menuShortcut: Font { font(Theme.Typography.menuShortcut, .callout) }
        var menuIcon: Font { font(Theme.Typography.menuIcon, .body) }

        /// 文本样式对应的 AppKit 版本，用于 `NSTextView` 绘制与 SwiftUI 并排显示的文字。
        func textNSFont(
            _ style: NSFont.TextStyle, weight: NSFont.Weight? = nil, monospaced: Bool = false
        ) -> NSFont {
            let base = nsFont(style)
            if monospaced { return .monospacedSystemFont(ofSize: base.pointSize, weight: weight ?? .regular) }
            guard let weight else { return base }
            return .systemFont(ofSize: base.pointSize, weight: weight)
        }

        /// 组合方式与 `Theme` 一致：样式决定字面，显式传入的 weight 会覆盖它。
        private func font(
            _ base: Font, _ style: NSFont.TextStyle, _ weight: Font.Weight? = nil
        )
            -> Font
        {
            guard scale != 1 else { return base }
            let scaled = Font(nsFont(style))
            return weight.map(scaled.weight) ?? scaled
        }

        /// 保留自身的 descriptor，使 `.headline` 仍为 Bold、`.caption2` 仍为 Medium，而不会被减淡。
        private func nsFont(_ style: NSFont.TextStyle) -> NSFont {
            let base = NSFont.preferredFont(forTextStyle: style)
            guard scale != 1 else { return base }
            return NSFont(descriptor: base.fontDescriptor, size: scaledPoints(base.pointSize, scale)) ?? base
        }
    }
}

/// 取整到整点：小数行距会让键帽边缘与渐隐遮罩落在非整数像素上。
private func scaledPoints(_ value: CGFloat, _ scale: CGFloat) -> CGFloat {
    scale == 1 ? value : (value * scale).rounded()
}

extension EnvironmentValues {
    /// 默认为 `.standard`，因此调色板之外复用 `DesignSystem` 的视图不会被缩放。
    @Entry var metrics = InterfaceMetrics.standard
}
