// 文件职责：集中定义 GearMac 全局设计 token（间距、圆角、模糊、尺寸、时长、动效、字体、颜色）与玻璃控件扩展。
// 分层：UI（DesignSystem）；纯静态取值、无副作用，所有深色颜色都按强制深色构建实际发出的字面值给定。
import QuartzCore
import SwiftUI

/// 全局设计 token 集中定义；每个深色颜色都等于强制深色构建实际发出的字面值。
enum Theme {
    /// 全局间距 token。
    enum Spacing {
        static let xxs: CGFloat = 2
        static let dictationWaveGap: CGFloat = 3
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 10
        static let xl: CGFloat = 12
        /// GearMac 对话框内容的外侧内边距。
        static let dialogInset: CGFloat = 18
        static let xxl: CGFloat = 20
        /// 计算器答案卡更宽松的垂直留白。
        static let xxxl: CGFloat = 28
        /// 分类标题下方的间距，所有命令面板列表的 `SectionHeader` 共用。
        static let sectionHeaderBottom: CGFloat = 4
        /// 最后一条消息下方的留白，使其操作行归属该消息而不至于贴到底部栏。
        static let chatTranscriptBottom: CGFloat = 28
        /// 流式输出会在读者下滚时不断增高对话区，因此不能以「精确触底」作为判断条件。
        static let chatFollowTailSlack: CGFloat = 44
        /// 对话行之间额外的行距，使长回复读起来像分段落的文字。
        static let chatLine: CGFloat = 4
        /// 除首个标题外每个标题上方的间距，读起来像上一节的收束。
        static let sectionSpacing: CGFloat = 12
        /// Emoji 单元格需要稍大的间隔，使相邻分类的网格彼此可区分。
        static let emojiSectionSpacing: CGFloat = 14
    }

    /// 全局圆角 token。
    enum Radius {
        static let panel: CGFloat = 26
        static let row: CGFloat = 10
        /// Emoji 单元格比列表行更宽松，因此圆角取大一档。
        static let emojiCell: CGFloat = 12
        static let menu: CGFloat = 6
        /// 弹出菜单行背后的悬停高亮圆角。
        static let menuRow: CGFloat = 10
        /// 头部弹出按钮的圆角；底部动作胶囊仍保持完整胶囊形。
        static let barControl: CGFloat = 8
        static let menuPanel: CGFloat = 16
        /// 对话框面板内部主题图标的圆角块。
        static let dialogSymbol: CGFloat = 16
        /// 对话框与 HUD 表面的圆角，使对话框与命令面板看起来同族。
        static let dialog: CGFloat = 20
        static let thumbnail: CGFloat = 6
        /// 用于足够小的形状：若用 `thumbnail` 的圆角会被磨成圆形。
        static let glyph: CGFloat = 2
        /// 包裹方形缩略图的胶囊；完整胶囊形会与缩略图自身的圆角冲突。
        static let attachmentChip: CGFloat = 8
        static let card: CGFloat = 10
        /// 房间预览中「即将成为窗口」的卡片，按真实窗口而非列表行取圆角。
        static let roomCard: CGFloat = 16
        static let keyCap: CGFloat = 6
        /// 设置中快捷键录制器的键帽圆角——小于命令面板的 `keyCap` 胶囊。
        static let recorderKeyCap: CGFloat = 4
        static let tooltip: CGFloat = 8
    }

    /// 全局模糊半径 token。
    enum Blur {
        /// 在原始字号下已无法辨认，又不会把整行涂成一片；真正起隐藏作用的是字符替换。
        static let redaction: CGFloat = 3
    }

    /// 全局尺寸 token（宽高、图标与控件大小）。
    enum Size {
        static let panelWidth: CGFloat = 750
        static let panelHeight: CGFloat = 475
        /// 首次打开时的尺寸，也是最小值：再小标题栏自身的元素就会互相重叠。
        static let noteWindow = CGSize(width: 440, height: 180)
        /// 便签窗口随内容增高的上限，超过后编辑器改为滚动。
        static let noteWindowMaxHeight: CGFloat = 860
        static let noteEditorInset: CGFloat = 16
        /// 小于水平内边距，使首行紧贴标题栏下方。
        static let noteEditorTopInset: CGFloat = 6
        static let noteSearchHeight: CGFloat = 34
        /// 便签切换弹窗的尺寸，独立于可能只有 180pt 高的便签窗口。
        static let noteSwitcher = CGSize(width: 300, height: 240)
        static let noteSwitcherEmptyHeight: CGFloat = 96
        static let noteSwitcherDrop: CGFloat = 56
        /// 与所有菜单一样宽度固定；高度正好是四个标题行。
        static let noteHeadingMenu = CGSize(
            width: 220, height: menuRowHeight * 4 + menuRowSpacing * 3 + Spacing.sm * 2)
        static let noteFooterHeight: CGFloat = 28
        /// 容纳启动器 36pt 动作胶囊，并保留与其自身栏位相同的边距。
        static let noteTitlebar: CGFloat = 52
        /// 左右对称，使标题在避开交通灯与胶囊按钮后仍居于窗口中央。
        static let noteTitleInset: CGFloat = 120
        /// 9pt 会挤到命令面板 26pt 的圆角，因此 Notes 把交通灯放得更靠内。
        static let noteTrafficLightInset: CGFloat = 20
        /// 命令面板顶边上方占可见高度的比例；面板向下增长。
        static let paletteTopMarginFraction: CGFloat = 0.18
        static let headerHeight: CGFloat = 44
        /// 头部图标的固定槽位，使搜索框在所有模式下都从同一 x 坐标开始。
        static let headerIconSlot: CGFloat = 22
        /// 字段栏把搜索框挤到的最窄宽度：仅够光标与几个字符。
        static let searchFieldMinWidth: CGFloat = 60
        /// 搜索行上方的空间，保持恒定，使输入时栏位不会跳动。
        static let headerPadding: CGFloat = 10
        /// 收起后的紧凑栏：搜索行居中于上下对标的 `headerPadding` 留白中。
        static let compactHeight: CGFloat = headerHeight + headerPadding * 2
        /// 拖动中的命令面板距不可见的垂直中线多近才算对齐吸附。
        static let paletteSnapDistance: CGFloat = 8
        /// 恢复保存的位置时，屏幕上至少要留出这么多栏位宽度才仍然可抓取。
        static let paletteMinimumVisible: CGFloat = 44
        static let dropGuideDash: CGFloat = 8
        static let dropGuideGap: CGFloat = 12
        static let dropGuideWidth: CGFloat = 2
        static let dropGuideCombinedFlashTolerance: CGFloat = 6
        static let dropGuideFadeThreshold: CGFloat = 36
        static let dropGuideFadeDistance: CGFloat = 180
        static let bottomBarHeight: CGFloat = 52
        /// `BarButton` 的悬停胶囊高度，底部按钮组与头部筛选器共用。
        static let barButtonHeight: CGFloat = 28
        static let rowIcon: CGFloat = 24
        static let resultRowIcon: CGFloat = 26
        /// 为次要标签着色的圆点，类似「日历」App 用颜色标记事件所属日历。
        static let colorDot: CGFloat = 8
        /// 日程行中位于图标与标题之间的日历颜色条。
        static let calendarBarWidth: CGFloat = 3
        static let calendarBarHeight: CGFloat = 18
        static let keyCap: CGFloat = 18
        /// 设置中快捷键录制器的键帽尺寸——小于命令面板的 `keyCap` 胶囊。
        static let recorderKeyCap: CGFloat = 16
        /// 固定宽度，使录制器不会随绑定值变化而改变尺寸。
        static let shortcutRecorder: CGFloat = 120
        /// 录制器浮层中一行文字的高度。
        static let shortcutPopoverLine: CGFloat = 14
        /// 由各条带高度累加得到；宽度由 `callout-test` 固定校验。
        static let shortcutPopover = CGSize(
            width: 132,
            height: Spacing.sm * 2 + heroKeyCap + Spacing.sm + shortcutPopoverLine + Spacing.sm
                + compactKeyCap + calloutCaretHeight)
        /// 浮层的指向箭头：尖端圆润的三角形。
        static let calloutCaretWidth: CGFloat = 15
        static let calloutCaretHeight: CGFloat = 7
        static let calloutCaretTip: CGFloat = 2.5
        /// 键帽尺寸：`compact` 用于提示、`keyCap` 为标准、`hero` 用于键帽本身就是内容时。
        static let compactKeyCap: CGFloat = 15
        static let heroKeyCap: CGFloat = 22
        static let menuButton: CGFloat = 36
        static let noteGlyph: CGFloat = 16
        static let noteEmptyGlyph: CGFloat = 28
        /// 聊天消息底部图标的点击目标尺寸；其中的小符号浮在此区域内。
        static let chatMessageAction: CGFloat = 16
        /// 一像素宽的 Markdown 分隔线与表格表头分隔线。
        static let hairline: CGFloat = 1
        static let markdownListMarker: CGFloat = 20
        static let markdownQuoteBar: CGFloat = 2
        /// 聊天输入框上下文环的线宽，轨道与进度部分相同。
        static let contextRingStroke: CGFloat = 2
        /// 聊天窗口的拖放轮廓线宽及其虚线长度。
        static let dropHintStroke: CGFloat = 2
        static let dropHintDash: CGFloat = 6
        /// 卸载列表中行首复选框/锁形图标的尺寸。
        static let checkbox: CGFloat = 16
        static let clipboardListWidth: CGFloat = 290
        /// 横条中单张条目卡片的大小。
        static let clipboardCard = CGSize(width: 170, height: 170)
        /// 卡片头部来源图标的槽位。
        static let clipboardCardIcon: CGFloat = 16
        /// 标签行尾部搜索框的固定宽度。
        static let clipboardSearchEntry: CGFloat = 180
        /// 横条整体高度：由头部、标签行、卡片行及其内边距累加而来。
        static var clipboardBarHeight: CGFloat {
            barButtonHeight + clipboardCard.height + Spacing.xxs * 2 + Spacing.xs * 2
                + Spacing.xxl * 2
        }
        /// Emoji 网格与面板两侧边缘之间对称的留白。
        static let emojiGridInset: CGFloat = 16
        static let emojiCell: CGFloat = 56
        static let menuWidth: CGFloat = 276
        static let actionMenuWidth: CGFloat = 320
        /// 剪贴板类型筛选菜单的宽度；`menuWidth` 对六个短行来说太宽。
        static let clipboardFilterMenuWidth: CGFloat = 200
        static let fileSearchFilterMenuWidth: CGFloat = 200
        /// 足以容纳最长分类标题 "Shapes & Punctuation"。
        static let emojiCategoryMenuWidth: CGFloat = 220
        /// 直接指定高度而非靠内边距撑开：下方的行数上限按行计数，否则限高菜单会截在行中间。
        static let menuRowHeight: CGFloat = menuIcon + Spacing.md * 2
        static let menuRowSpacing: CGFloat = 1
        /// 直接指定高度而非实测：`viewportHeight` 会统计标题高度，限高菜单才能正好落在行边界上。
        static let menuSectionHeader: CGFloat = 16
        /// 五行加第六行的一半，使限高菜单看起来可滚动而非被截断。
        static let menuVisibleRows: CGFloat = 5.5
        /// 取整：奇数行距的半行会让玻璃边缘落在半像素上。
        static var menuRowsMaxHeight: CGFloat {
            (menuVisibleRows * (menuRowHeight + menuRowSpacing)).rounded()
        }
        /// 菜单行的图标槽位，尺寸与符号图标行一致，使符号与应用图标行看起来相同。
        static let menuIcon: CGFloat = 20
        /// 菜单图标槽内的品牌标记，尺寸按符号的视觉重量匹配。
        static let menuBrandIcon: CGFloat = 14
        /// 同一品牌标记在头部栏按钮中的尺寸，与其旁边的符号一致。
        static let barBrandIcon: CGFloat = 12
        /// 对话中已发送图片的尺寸；待发送的则在输入框胶囊中显示为小预览。
        static let chatImageThumb: CGFloat = 96
        static let chatAttachmentGlyph: CGFloat = 16
        /// 待发送文件在胶囊内的预览尺寸，小于胶囊高度以保证看起来在内部。
        static let chatAttachmentThumb: CGFloat = 18
        /// 窗口输入框的移除按钮；虽小，却是误粘贴后能够挖回的关键。
        static let chatAttachmentRemove: CGFloat = 14
        /// 比胶囊内部的间距更紧，使缩略图看起来填满胶囊。
        static let chatAttachmentInset: CGFloat = 3
        /// 文件搜索的预览舞台：与视频相同的宽高比，高度足以读完一页内容。
        static let previewAspectRatio: CGFloat = 16 / 9
        /// 打开尺寸也是缩放下限：宽度取「快捷操作」行，高度取侧边栏全高。
        static let settingsWindow = CGSize(width: 900, height: 700)
        /// 设置侧边栏：固定列宽，足以容纳 "Window Management"。
        static let settingsSidebar: CGFloat = 215
        /// 详情列允许的最窄宽度，再窄分组行的控件就会开始重叠。
        static let settingsDetailMinimum: CGFloat = 420
        static let settingsRowIcon: CGFloat = 20
        /// 侧边栏彩色块内图标的尺寸；加上色块内边距后正好等于行图标尺寸。
        static let settingsSidebarGlyph: CGFloat = 14
        /// AI 聊天的初始窗口尺寸；之后由用户调整并自动保存。
        static let aiChatWindow = CGSize(width: 960, height: 660)
        static let aiChatWindowMinimum = CGSize(width: 680, height: 440)
        static let aiChatSidebarMinimum: CGFloat = 240
        static let aiChatSidebarMaximum: CGFloat = 340
        /// 侧边栏搜索胶囊的高度，取一行的高度以与下方列表对齐。
        static let aiChatSearchField: CGFloat = 28
        static let aiChatDetailMinimum: CGFloat = 440
        /// 对话区与输入框所在列的宽度上限，再宽正文行就不易阅读。
        static let aiChatReadingWidth: CGFloat = 760
        static let aiChatComposerMaxLines: CGFloat = 15
        static let aiChatComposerHeightFraction: CGFloat = 0.30
        /// 输入框所在行所有控件（含发送）的统一高度，使整行看起来是一条线。
        static let aiChatComposerControl: CGFloat = 28
        /// 该行所有图标的统一槽位，使加号与品牌标记视觉重量一致。
        static let aiChatComposerGlyph: CGFloat = 16
        static let chatContextGauge: CGFloat = 14
        /// 来源胶囊标题在中间截断前的宽度，使三个胶囊能同行显示。
        static let chatSourceTitle: CGFloat = 200
        /// 上下文卡片的宽度：容纳标签列与取值列，并为模型名留出空间。
        static let chatContextCard: CGFloat = 300
        /// 分组 `Form` 行中控件的高度。
        static let settingsControlHeight: CGFloat = 28
        static let emojiSkinToneGlyph: CGFloat = 13
        /// 单个密度预览的尺寸；Emoji 设置详情面板可并排容纳五个。
        static let emojiSettingsGridPreview: CGFloat = 72
        /// 布局编辑器尺寸。高度固定，使选中条目不会改变面板大小。
        static let layoutEditorSheet = CGSize(width: 900, height: 660)
        /// 检查器列宽；预览占据剩余空间，保持约 2:1 的分栏比例。
        static let layoutInspectorColumn: CGFloat = 300
        /// 条目下拉列表的宽度，比按钮更宽，使较长的应用名仍可读。
        static let layoutEntryPopover: CGFloat = 260
        /// 预览矩形内应用图标的尺寸，小到窄窗口也能显示完整。
        static let layoutPreviewIcon: CGFloat = 22
        /// 预览下方带编号的显示器标签尺寸。
        static let layoutDisplayTab: CGFloat = 24
        /// 检查器中所有控件（输入框、下拉、添加按钮）统一的高度。
        static let layoutControlHeight: CGFloat = 28
        /// 数值输入框中单位的固定槽宽，使 "%" 与 "pt" 的数字起始位置一致。
        static let layoutFieldUnit: CGFloat = 16
        static let layoutPositionGlyph = CGSize(width: 26, height: 19)
        static let layoutPositionStroke: CGFloat = 1.5
        /// 位置单元格的可点击行高；图示浮在其中，使整个单元格都可点击。
        static let layoutPositionCell: CGFloat = 34
        /// AI 服务商面板尺寸：仿「邮件」账户页布局，服务商列表在左、所选详情在右。
        static let aiProvidersPanel = CGSize(width: 840, height: 520)
        static let aiProvidersList: CGFloat = 262
        /// 控件稳定后系统在分段标签两侧保留的固有留白。
        static let segmentLabelInset: CGFloat = 13
        static let aiVariableName: CGFloat = 170
        /// Codex 用量窗口进度条的宽度，与旁边的 "72% left" 读数并排。
        static let aiUsageBar: CGFloat = 110
        /// 设置编辑器弹窗（自定义命令、片段）的固定宽度，高度随内容。
        static let editorSheetWidth: CGFloat = 480
        /// 这些弹窗内多行文本框的高度；超出时滚动而不是撑大面板。
        static let editorTextHeight: CGFloat = 120
        /// 确认 HUD 的宽度上限，及其距屏幕底边的距离。
        static let hudMaxWidth: CGFloat = 420
        static let hudEdgeOffset: CGFloat = 48
        /// 提问与通知保持紧凑；控件仍保留原生组件所需的空间。
        static let dialogCompactWidth: CGFloat = 290
        /// GearMac 自有控件对话框：宽度固定，高度由 SwiftUI 内容实测决定。
        static let dialogWidth: CGFloat = 420
        static let dialogButtonHeight: CGFloat = menuButton - 2
        /// 对话框顶部主题标识及其固定色块尺寸。
        static let dialogSymbol: CGFloat = 28
        static let dialogSymbolContainer: CGFloat = 52
        /// 对话框附件图标与音量 HUD 图标的共用尺寸。
        static let dialogIcon: CGFloat = 32
        /// 在对话框宽度下取 16:9，使两个界面看起来同族。
        static let cameraPreview = CGSize(width: 420, height: 236)
        /// 同样 16:9 但更宽：独立摄像头窗口本身就是主体界面，而不是某个界面上的确认层。
        static let cameraStage = CGSize(width: 560, height: 315)
        /// 比对话框更宽：快捷操作的结果是需要阅读的正文，而不是一句待确认的话。
        static let quickActionPanel: CGFloat = 520
        /// 与标题的大写字高匹配；行级大小的图标放在旁边会像出错。
        static let quickActionHeaderIcon: CGFloat = 14
        /// 各栏位可读区下方的渐隐区间，按标题背后的文字长度衡量。
        static let quickActionScrollFade: CGFloat = 40
        /// 超过此高度结果改为滚动，使长摘要不会把面板撑出屏幕。
        static let quickActionPanelBody: CGFloat = 320
        /// 保证仅两词的语法修正不会把面板压缩成一条窄缝。
        static let quickActionPanelMinBody: CGFloat = 44
        /// 任意音量或静音指令后短暂显示的音量 HUD 尺寸。
        static let hudWidth: CGFloat = 200
        static let hudHeight: CGFloat = 100
        static let dictationPanel = CGSize(width: 144, height: 44)
        static let dictationWaveBar: CGFloat = 2
        /// HUD 中只读音量条的高度。
        static let volumeTrackHeight: CGFloat = 6
        /// 音量读数的固定槽宽，按可能出现的最宽字符串预留。
        static let volumeReadout: CGFloat = 38
        static let roomCardTitleBar: CGFloat = 40
        static let roomCardStroke: CGFloat = 2
        static let roomCardShadowRadius: CGFloat = 24
        static let roomCardShadowOffset: CGFloat = 8
        static let roomCardDot: CGFloat = 8
        static let roomCardIcon: CGFloat = 64
        static let roomCardIconLarge: CGFloat = 96
        /// 低于此高度卡片只剩一条窄边，放不下图标。
        static let roomCardIconMinHeight: CGFloat = 160
        static let roomCardLargeIconMinSide: CGFloat = 320
    }

    /// 全局动画与时序时长 token。
    enum Duration {
        /// 每个 HUD 的停留时长；一句提示比一个音量读数需要更久。
        static let messageHUD: TimeInterval = 2.4
        static let volumeHUD: TimeInterval = 1.6
        /// 无边框界面的进出场时长；退场更短，因此感觉利落。
        static let enter: TimeInterval = 0.18
        static let exit: TimeInterval = 0.12
        /// 对话框随启动器变暗一同出现；其淡入是更短的次节拍。
        static let dialogEnter: TimeInterval = 0.12
        static let dialogExit: TimeInterval = 0.10
        /// 悬停 `Tooltip` 的淡入淡出时长，其前的等待只有刻意悬停才会持续到。
        static let tooltip: TimeInterval = 0.15
        static let dropGuide: TimeInterval = 0.24
        static let tooltipDelay: TimeInterval = 0.4
        /// 指针下控件亮起的时长；足够短才像即时响应。
        static let hover: TimeInterval = 0.12
        /// 弹出菜单箭头在收起与展开方向之间旋转的时长。
        static let menuChevron: TimeInterval = 0.34
        static let copyFeedback: TimeInterval = 1.2
        static let chatFooter: TimeInterval = 0.12
        /// 设置搜索结果把所属区块滚动到可视区，随后标记该区块的脉冲时长。
        static let settingsReveal: TimeInterval = 0.28
        static let settingsFlash: TimeInterval = 2.0
        static let settingsFlashOut: TimeInterval = 0.6
        /// 房间预览卡片滑向下一个位置的时长；进出场卡片则淡入淡出。
        static let roomGlide: TimeInterval = 0.32
        static let roomCardEnter: TimeInterval = 0.2
        static let roomCardExit: TimeInterval = 0.18
        static let roomSettle: TimeInterval = 0.25
    }

    /// 房间预览卡片专用动效。
    enum RoomMotion {
        /// 离场快、稳定慢，使卡片读起来像它即将成为的窗口。
        static let glide = Animation.timingCurve(0.2, 0, 0, 1, duration: Theme.Duration.roomGlide)
    }

    /// 对话框进出场动效参数。
    enum DialogMotion {
        static let offset: CGFloat = 3
        static let initialOpacity: CGFloat = 0.08
    }

    /// GearMac 自有菜单使用的动效；扩展提供的面板保留其自身行为。
    @MainActor
    enum MenuMotion {
        static let entryScale: CGFloat = 0.94
        static let maximumScale: CGFloat = 1.003
        static let exitScaleDelta: CGFloat = 0.04
        static let expansionDuration: TimeInterval = 0.10
        static let settleDuration: TimeInterval = 0.05
        static let exitDuration: TimeInterval = 0.18
        static let expansionTiming = CAMediaTimingFunction(controlPoints: 0.2, 0.7, 0.2, 1)
        static let settleTiming = CAMediaTimingFunction(controlPoints: 0.42, 0, 0.58, 1)
        static let exitTiming = CAMediaTimingFunction(controlPoints: 0.4, 0, 1, 1)
        /// 起步迅速，随后平缓地过渡到箭头的最终方向。
        static let chevronAnimation = Animation.timingCurve(
            0.16, 1, 0.3, 1, duration: Theme.Duration.menuChevron)
    }

    /// 使用系统文本样式而非写死字号，以遵循 Dynamic Type。
    enum Typography {
        /// 同一字号服务两个框架：`TextTrailingDragHandle` 需要测量输入框实际渲染的结果。
        static let searchFieldSize: CGFloat = 20
        static let searchField = Font.system(size: searchFieldSize, weight: .regular)
        /// `NSFont` 不是 `Sendable`，因此需要隔离；其读取方本来都是视图。
        @MainActor static let searchFieldNSFont = NSFont.systemFont(
            ofSize: searchFieldSize, weight: .regular)
        static let headerIcon = Font.system(size: 18, weight: .medium)
        static let rowTitle = Font.body
        static let rowTrailing = Font.callout
        static let sectionHeader = Font.subheadline.weight(.medium)
        /// 无边框面板自身的标题，用于命名该界面而非其中的某个区块。
        static let panelTitle = Font.headline
        /// 计算器答案卡上的大号数值行（源单位与目标单位两侧共用）。
        static let calcResult = Font.title
        static let keyCap = Font.caption
        /// 需与 `KeyCapChip.Scale` 中对应的 `Size` 配套使用。
        static let compactKeyCap = Font.caption2
        static let heroKeyCap = Font.body
        static let markdownHeading1 = Font.title2.weight(.semibold)
        static let markdownHeading2 = Font.title3.weight(.semibold)
        static let markdownHeading3 = Font.headline
        static let code = Font.system(.callout, design: .monospaced)
        static let inlineCode = Font.body.monospaced()
        static let bar = Font.callout.weight(.medium)
        /// 输入框旁待发送附件名的字体；其 NSFont 用于测量胶囊宽度。
        static let chip = Font.callout
        @MainActor static let chipNSFont = NSFont.preferredFont(forTextStyle: .callout)
        /// 下拉控件尾部箭头的字体，刻意小于其前面的标签。
        static let disclosure = Font.caption.weight(.semibold)
        static let menuRow = Font.body
        static let menuShortcut = Font.callout
        static let menuIcon = Font.body
        static let menuSymbolSize: CGFloat = 14
        static let menuSymbolWeight = Font.Weight.medium
        /// 底部横条卡片内的多行预览文本。
        static let cardText = Font.footnote
        /// 卡片元信息（相对时间、字符数）的字体。
        static let cardMeta = Font.caption2
        static let noteTitle = Font.headline
        /// 输入框行的图标字体；发送箭头更粗，停止方块则相应更小。
        static let composerSymbol = Font.system(size: 13, weight: .medium)
        static let composerSend = Font.system(size: 13, weight: .bold)
        static let composerStop = Font.system(size: 10, weight: .bold)
    }

    /// 全局颜色 token，按当前外观自适应取值。
    enum Colors {
        /// 按窗口的 `effectiveAppearance` 解析，使颜色随外观切换自动重绘。
        static func adaptive(dark: NSColor, light: NSColor) -> Color {
            Color(nsColor: NSColor(name: nil) { $0.isDark ? dark : light })
        }

        /// 透明度渐变（取反）：深色表面用白色墨水，浅色表面用黑色墨水。
        static func ramp(dark: Double, light: Double) -> Color {
            adaptive(dark: .srgbInk(1, alpha: dark), light: .srgbInk(0, alpha: light))
        }

        /// 与渐变相反：遮罩让深色表面更暗、浅色表面更亮。
        static let panelScrim = adaptive(dark: .srgbInk(0, alpha: 0.40), light: .srgbInk(1, alpha: 0.55))
        /// GearMac 内部的模态分层：对话框在前时启动器后退变暗。
        static let dialogDimming = adaptive(
            dark: .srgbInk(0, alpha: 0.34), light: .srgbInk(0, alpha: 0.34))
        /// 查找标记使用系统自带的黄色：所有匹配项浅色，当前项实色。
        static let findMatch = adaptive(
            dark: NSColor.systemYellow.withAlphaComponent(0.32),
            light: NSColor.systemYellow.withAlphaComponent(0.4))
        static let findCurrent = adaptive(
            dark: NSColor.systemYellow.withAlphaComponent(0.9),
            light: NSColor.systemYellow.withAlphaComponent(0.95))
        /// 两种外观下实色标记上都用黑色，如同荧光笔上的字迹保持可读。
        static let findCurrentInk = adaptive(
            dark: .srgbInk(0, alpha: 1), light: .srgbInk(0, alpha: 1))
        static let tooltipShadow = adaptive(
            dark: .srgbInk(0, alpha: 0.18), light: .srgbInk(0, alpha: 0.18))

        /// 选中填充色，所有列表共用以保证外观一致。
        static let selection = ramp(dark: 0.10, light: 0.09)
        /// 鼠标悬停：比选中更淡的一层，视觉上与选中区分。
        static let rowHover = ramp(dark: 0.05, light: 0.045)
        /// Emoji 网格外观：静置时为低调的底块，交互时给出两圈可辨识的描边。
        static let emojiCell = ramp(dark: 0.045, light: 0.04)
        static let emojiHoverBorder = ramp(dark: 0.42, light: 0.34)
        static let emojiSelectionBorder = ramp(dark: 0.92, light: 0.72)
        static let emojiInnerBorder = adaptive(
            dark: .srgbInk(0, alpha: 0.72), light: .srgbInk(1, alpha: 0.72))
        static let menuHover = ramp(dark: 0.10, light: 0.09)
        static let separator = ramp(dark: 0.10, light: 0.12)
        /// 小型控件底色：键帽胶囊与图标块。
        static let controlSurface = ramp(dark: 0.10, light: 0.08)
        /// 指针悬停时控件应比静置底色更亮一层。
        static let controlHover = ramp(dark: 0.16, light: 0.14)
        /// 按下的控件比悬停更强，使鼠标按下始终可见。
        static let controlPressed = ramp(dark: 0.24, light: 0.20)
        /// 控件描边：描边样式的键帽胶囊。
        static let border = ramp(dark: 0.20, light: 0.18)
        /// 透明度为 1，调用方可用 `.opacity` 调暗并正好落在原先的取值上。
        static let textPrimary = ramp(dark: 1.0, light: 1.0)
        static let textSecondary = ramp(dark: 0.60, light: 0.60)
        static let textTertiary = ramp(dark: 0.40, light: 0.42)
        static let menuSymbol = ramp(dark: 0.70, light: 0.70)
        static let noteText = ramp(dark: 0.90, light: 0.85)
        static let iconPlaceholder = ramp(dark: 0.06, light: 0.06)
        /// 引导页标题背后的淡色涂层。
        static let sheen = ramp(dark: 0.04, light: 0.04)
        /// 设置卡片底色：淡色表面，其描边同时充当行分隔线。
        static let cardFill = ramp(dark: 0.05, light: 0.04)
        static let cardStroke = ramp(dark: 0.10, light: 0.10)
        /// 两种外观下都用白色：磨砂会提亮玻璃，而浅色玻璃需要更多白色才看得出。
        /// 预览底版上的窗口。两种外观下都用白色，因为底版始终是深色。
        static let layoutPreviewWindow = adaptive(
            dark: .srgbInk(1, alpha: 0.22), light: .srgbInk(1, alpha: 0.28))
        /// 被选中的窗口，在被强调色描边看清之前就已足够显眼。
        static let layoutPreviewWindowSelected = adaptive(
            dark: .srgbInk(1, alpha: 0.38), light: .srgbInk(1, alpha: 0.44))
        /// 预览的底版：显示器在两种外观下都是深色，因此用 `adaptive` 而非 `ramp`。
        static let layoutPreviewGround = adaptive(
            dark: .srgbInk(0, alpha: 0.55), light: .srgbInk(0, alpha: 0.50))
        /// 房间预览背后模糊的桌面，压暗后只让新布局清晰可读。
        static let roomPreviewDim = adaptive(
            dark: .srgbInk(0, alpha: 0.18), light: .srgbInk(0, alpha: 0.18))
        /// 房间卡片在两种外观下都是实心窗口，使桌面不会透出。
        static let roomCardFill = adaptive(
            dark: .srgbInk(0.16, alpha: 0.94), light: .srgbInk(0.98, alpha: 0.94))
        static let roomCardStroke = Color.accentColor
        static let roomCardShadow = adaptive(
            dark: .srgbInk(0, alpha: 0.25), light: .srgbInk(0, alpha: 0.25))
        static let roomCardDot = ramp(dark: 0.25, light: 0.25)
        /// 设置搜索跳转到的区块标题背后的胶囊高亮。
        static let searchFlash = Color.accentColor.opacity(0.35)
        /// 棋盘格的两个方块，用于在展示带透明度的颜色时作为底衬。
        static let checkerLight = Color(nsColor: .srgbInk(1, alpha: 0.22))
        static let checkerDark = Color(nsColor: .srgbInk(0, alpha: 0.22))
        /// 应用标识的紫色，仅用于「关于」页支持提示的着色。
        static let brand = Color(red: 0.525, green: 0.231, blue: 1.0)
        /// 拖动命令面板时的落点指示线，以及松手会吸附归位时的颜色。
        static let dropGuide = ramp(dark: 0.35, light: 0.35)
        static let dropGuideArmed = Color.blue
        /// 对话框的标准默认动作色；破坏性默认动作仍保留语义红。
        static let primaryAction = Color.blue
        /// 破坏性色调：破坏性标签，以及 `.danger` 对话框的图标。
        static let destructive = Color.red
        /// 成功色调：`.success` 对话框的行首图标。
        static let success = Color.green
        /// 警示色调，程度低于破坏性：聊天上下文即将占满。
        static let warning = Color.orange
        /// 发送按钮的圆盘与箭头：输入区最醒目的标记，相对页面反色。
        static let composerSend = ramp(dark: 0.92, light: 0.92)
        static let composerSendInk = adaptive(dark: .srgbInk(0, alpha: 0.85), light: .srgbInk(1, alpha: 1))
        /// 窗口自身的页面底色，供需要遮住其下对话内容的浮动卡片使用。
        static let windowSurface = Color(nsColor: .windowBackgroundColor)
        /// 文件将落入的位置：聊天窗口的虚线轮廓颜色。
        static let dropTarget = Color.accentColor
        /// 进度色调：后台任务仍在运行时消息胶囊中的转圈指示器。
        static let progress = Color.blue
        /// 命令输出窗口的页面：日志直接铺在其上的平整表面。
        static let terminalSurface = adaptive(
            dark: .srgbInk(0.07, alpha: 1), light: .srgbInk(0.99, alpha: 1))
    }
}

extension View {
    /// 悬浮玻璃控件表面：macOS 26 用可交互 Liquid Glass；旧系统回落到超薄材质。
    /// 旧系统没有玻璃自带的悬停高亮，如需交互反馈由调用方自行补 .onHover。
    @ViewBuilder
    func frosted(in shape: some Shape) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular.interactive(), in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
        }
    }

    /// 静态玻璃表面：与 frosted 的区别是不带交互高亮；既有 .glassEffect(.regular) 调用统一
    /// 收敛到这里，保证 macOS 26 上行为与收敛前完全一致。
    @ViewBuilder
    func glassSurface(in shape: some Shape) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
        }
    }

    /// 玻璃按钮样式：macOS 26 用系统 Glass 样式；旧系统以超薄材质胶囊近似。
    /// 调用方原有的 .buttonBorderShape 等后续修饰照旧生效。
    @ViewBuilder
    func glassButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(FallbackGlassButtonStyle())
        }
    }
}

/// macOS 15 回落：以超薄材质胶囊近似 Glass 按钮，按下时降低不透明度作为反馈。
struct FallbackGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.ultraThinMaterial, in: .capsule)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
