// 文件职责：窗口管理（WindowManagement）功能的本地化键与中英词表。
// 分层：Model（本地化）；自包含，不引用其他功能的键。
import Foundation

/// 窗口管理（命令、布局、房间、自定义尺寸）的文案键。
enum WindowKey: String, LocalizableKey {
    // 通用字段与操作
    case fieldName = "window.field.name"
    case fieldSize = "window.field.size"
    case fieldOffset = "window.field.offset"
    case fieldPosition = "window.field.position"
    case fieldWidth = "window.field.width"
    case fieldHeight = "window.field.height"
    case fieldHorizontalOffset = "window.field.horizontalOffset"
    case fieldVerticalOffset = "window.field.verticalOffset"
    case actionEdit = "window.action.edit"
    case actionDelete = "window.action.delete"
    case actionDuplicate = "window.action.duplicate"
    case actionCancel = "window.action.cancel"
    case actionSave = "window.action.save"
    case actionShowInLauncher = "window.action.showInLauncher"
    case actionRun = "window.action.run"
    case actionEnter = "window.action.enter"
    case actionChooseWindows = "window.action.chooseWindows"
    case deleteTitle = "window.delete.title"
    case permissionTitle = "window.permission.title"
    case permissionMessage = "window.permission.message"
    case permissionRecovery = "window.permission.recovery"

    // 汇总与计数
    case summaryWindowOne = "window.summary.windowOne"
    case summaryWindowMany = "window.summary.windowMany"
    case summaryDisplays = "window.summary.displays"
    case sizeSummaryOffset = "window.summary.sizeOffset"
    case skipDisplayOne = "window.summary.skipDisplayOne"
    case skipDisplayMany = "window.summary.skipDisplayMany"
    case skipEntryOne = "window.summary.skipEntryOne"
    case skipEntryMany = "window.summary.skipEntryMany"

    // 校验错误
    case errorLayoutEmptyName = "window.error.layout.emptyName"
    case errorLayoutDuplicateName = "window.error.layout.duplicateName"
    case errorLayoutNoEntries = "window.error.layout.noEntries"
    case errorNameNullCharacter = "window.error.name.nullCharacter"
    case errorSizeEmptyName = "window.error.size.emptyName"
    case errorSizeDuplicateName = "window.error.size.duplicateName"
    case errorRoomEmptyName = "window.error.room.emptyName"
    case errorRoomDuplicateName = "window.error.room.duplicateName"
    case errorRoomNoWindows = "window.error.room.noWindows"

    // 窗口命令分组
    case groupHalves = "window.command.group.halves"
    case groupQuarters = "window.command.group.quarters"
    case groupFourths = "window.command.group.fourths"
    case groupThirds = "window.command.group.thirds"
    case groupSizing = "window.command.group.sizing"
    case groupMoving = "window.command.group.moving"
    case groupFullscreen = "window.command.group.fullscreen"
    case groupSpaces = "window.command.group.spaces"

    // 窗口命令名称
    case commandLeftHalf = "window.command.leftHalf"
    case commandRightHalf = "window.command.rightHalf"
    case commandTopHalf = "window.command.topHalf"
    case commandBottomHalf = "window.command.bottomHalf"
    case commandTopLeftQuarter = "window.command.topLeftQuarter"
    case commandTopRightQuarter = "window.command.topRightQuarter"
    case commandBottomLeftQuarter = "window.command.bottomLeftQuarter"
    case commandBottomRightQuarter = "window.command.bottomRightQuarter"
    case commandFirstThreeFourths = "window.command.firstThreeFourths"
    case commandLastThreeFourths = "window.command.lastThreeFourths"
    case commandFirstThird = "window.command.firstThird"
    case commandCenterThird = "window.command.centerThird"
    case commandLastThird = "window.command.lastThird"
    case commandFirstTwoThirds = "window.command.firstTwoThirds"
    case commandLastTwoThirds = "window.command.lastTwoThirds"
    case commandMaximize = "window.command.maximize"
    case commandAlmostMaximize = "window.command.almostMaximize"
    case commandReasonableSize = "window.command.reasonableSize"
    case commandMaximizeHeight = "window.command.maximizeHeight"
    case commandMaximizeWidth = "window.command.maximizeWidth"
    case commandCenter = "window.command.center"
    case commandCenterHalf = "window.command.centerHalf"
    case commandCenterTwoThirds = "window.command.centerTwoThirds"
    case commandMakeLarger = "window.command.makeLarger"
    case commandMakeSmaller = "window.command.makeSmaller"
    case commandRestore = "window.command.restore"
    case commandMoveLeft = "window.command.moveLeft"
    case commandMoveRight = "window.command.moveRight"
    case commandMoveUp = "window.command.moveUp"
    case commandMoveDown = "window.command.moveDown"
    case commandNextDisplay = "window.command.nextDisplay"
    case commandPreviousDisplay = "window.command.previousDisplay"
    case commandToggleFullscreen = "window.command.toggleFullscreen"
    case commandPreviousSpace = "window.command.previousSpace"
    case commandNextSpace = "window.command.nextSpace"

    // 锚点
    case anchorTopLeft = "window.anchor.topLeft"
    case anchorTop = "window.anchor.top"
    case anchorTopRight = "window.anchor.topRight"
    case anchorLeft = "window.anchor.left"
    case anchorCenter = "window.anchor.center"
    case anchorRight = "window.anchor.right"
    case anchorBottomLeft = "window.anchor.bottomLeft"
    case anchorBottom = "window.anchor.bottom"
    case anchorBottomRight = "window.anchor.bottomRight"

    // 半屏循环
    case cycleNone = "window.cycle.none"
    case cycleSizes = "window.cycle.sizes"
    case cycleDisplays = "window.cycle.displays"
    case cycleNoneDetail = "window.cycle.none.detail"
    case cycleSizesDetail = "window.cycle.sizes.detail"
    case cycleDisplaysDetail = "window.cycle.displays.detail"

    // 房间布局种类
    case roomKindAuto = "window.roomKind.auto"
    case roomKindFocus = "window.roomKind.focus"
    case roomKindStack = "window.roomKind.stack"
    case roomKindColumns = "window.roomKind.columns"
    case roomKindGrid = "window.roomKind.grid"
    case roomKindCustom = "window.roomKind.custom"
    case roomKindSaved = "window.roomKind.saved"

    // 快捷键预设
    case presetRectangle = "window.preset.rectangle"
    case presetSpectacle = "window.preset.spectacle"

    // 设置页
    case settingsEnableTitle = "window.settings.enableTitle"
    case settingsEnableSubtitle = "window.settings.enableSubtitle"
    case settingsDeleteLayoutMessage = "window.settings.deleteLayoutMessage"
    case settingsCycling = "window.settings.cycling"
    case settingsGap = "window.settings.gap"
    case settingsGapDetail = "window.settings.gapDetail"
    case settingsShortcutPreset = "window.settings.shortcutPreset"
    case settingsShortcutPresetDetail = "window.settings.shortcutPresetDetail"
    case settingsChoose = "window.settings.choose"
    case settingsApply = "window.settings.apply"

    // 布局库
    case layoutsShowInLauncher = "window.layouts.showInLauncher"
    case layoutsSearchPrompt = "window.layouts.searchPrompt"
    case layoutsNew = "window.layouts.new"
    case layoutsCapture = "window.layouts.capture"
    case layoutsEmpty = "window.layouts.empty"
    case layoutsNoMatch = "window.layouts.noMatch"

    // 房间库
    case roomsShowInLauncher = "window.rooms.showInLauncher"
    case roomsEmpty = "window.rooms.empty"
    case roomsNew = "window.rooms.new"
    case roomsEnterHelp = "window.rooms.enterHelp"
    case roomsChooseHelp = "window.rooms.chooseHelp"

    // 自定义尺寸库
    case sizesNew = "window.sizes.new"

    // 布局编辑器
    case editorCaptureTitle = "window.editor.captureTitle"
    case editorNewTitle = "window.editor.newTitle"
    case editorEditTitle = "window.editor.editTitle"
    case inspectorSectionLayout = "window.inspector.sectionLayout"
    case inspectorNamePlaceholder = "window.inspector.namePlaceholder"
    case inspectorChooseIcon = "window.inspector.chooseIcon"
    case inspectorUsePreferredGap = "window.inspector.usePreferredGap"
    case inspectorUsePreferredGapDetail = "window.inspector.usePreferredGapDetail"
    case inspectorBringToFront = "window.inspector.bringToFront"
    case inspectorBringToFrontDetail = "window.inspector.bringToFrontDetail"

    // 预览
    case previewNoDisplay = "window.preview.noDisplay"
    case previewDisplayNotConnected = "window.preview.displayNotConnected"
    case previewNotConnectedLabel = "window.preview.notConnectedLabel"
    case previewCaptionNotConnected = "window.preview.captionNotConnected"
    case previewDescription = "window.preview.description"

    // 显示器页签
    case tabsDisplay = "window.tabs.display"
    case tabsDisplayLabel = "window.tabs.displayLabel"

    // 参数与条目
    case argumentTitle = "window.argument.title"
    case argumentNone = "window.argument.none"
    case argumentChooseFile = "window.argument.chooseFile"
    case argumentChooseFolder = "window.argument.chooseFolder"
    case argumentEnterURL = "window.argument.enterURL"
    case argumentQuicklinks = "window.argument.quicklinks"
    case entryAddLabel = "window.entry.addLabel"
    case entryNoApp = "window.entry.noApp"
    case entryEditingLabel = "window.entry.editingLabel"
    case entryRemove = "window.entry.remove"

    // 自定义尺寸编辑器
    case sizeEditorEditTitle = "window.sizeEditor.editTitle"
    case sizeEditorSubtitle = "window.sizeEditor.subtitle"
    case sizeEditorNamePlaceholder = "window.sizeEditor.namePlaceholder"
    case sizeEditorUnit = "window.sizeEditor.unit"

    // 房间选择器屏幕
    case roomPickerAddTo = "window.roomPicker.addTo"
    case roomPickerRemoveFrom = "window.roomPicker.removeFrom"
    case roomPickerSave = "window.roomPicker.save"
    case roomPickerReading = "window.roomPicker.reading"
    case roomPickerEmptyNoWindows = "window.roomPicker.emptyNoWindows"
    case roomPickerEmptyNoMatch = "window.roomPicker.emptyNoMatch"

    // 房间屏幕
    case roomsScreenChooseWindows = "window.roomsScreen.chooseWindows"
    case roomsScreenCreateRoom = "window.roomsScreen.createRoom"
    case roomsScreenEnterRoom = "window.roomsScreen.enterRoom"
    case roomsScreenNextLayout = "window.roomsScreen.nextLayout"
    case roomsScreenRemember = "window.roomsScreen.remember"
    case roomsScreenChooseWindowsEllipsis = "window.roomsScreen.chooseWindowsEllipsis"
    case roomsScreenDeleteRoom = "window.roomsScreen.deleteRoom"
    case roomsScreenEmpty = "window.roomsScreen.empty"
    case roomsListChooseWindowsFor = "window.roomsList.chooseWindowsFor"
    case roomsListCreateRoomNamed = "window.roomsList.createRoomNamed"
    case roomsListCurrent = "window.roomsList.current"
    case roomsListEditSubtitle = "window.roomsList.editSubtitle"
    case roomsListAccessibilityLayout = "window.roomsList.accessibilityLayout"
    case pickerListHidden = "window.pickerList.hidden"
    case pickerListMinimized = "window.pickerList.minimized"
    case pickerListAppOpensWithRoom = "window.pickerList.appOpensWithRoom"
    case pickerListAccessibilityPlace = "window.pickerList.accessibilityPlace"

    // 房间协调器
    case roomOnlyOneLayout = "window.room.onlyOneLayout"
    case roomNameMissing = "window.room.nameMissing"
    case roomPickOne = "window.room.pickOne"
    case roomSaveFailed = "window.room.saveFailed"
    case roomNoneOpen = "window.room.noneOpen"
    case roomRemembered = "window.room.remembered"
    case roomDeleteMessage = "window.room.deleteMessage"
    case roomEnterFailedTitle = "window.room.enterFailedTitle"
    case roomEnterFailedMessage = "window.room.enterFailedMessage"
    case roomMissing = "window.room.missing"
    case roomPermissionMessage = "window.room.permissionMessage"

    // 布局协调器
    case layoutNoWindowsToCapture = "window.layout.noWindowsToCapture"
    case layoutPermissionMessage = "window.layout.permissionMessage"
    case layoutRunFailedTitle = "window.layout.runFailedTitle"
    case layoutSaveFailedTitle = "window.layout.saveFailedTitle"
    case layoutSaveFailedMessage = "window.layout.saveFailedMessage"
    case layoutMissingAppOne = "window.layout.missingAppOne"
    case layoutMissingAppMany = "window.layout.missingAppMany"
    case layoutFailedAppOne = "window.layout.failedAppOne"
    case layoutFailedAppMany = "window.layout.failedAppMany"
    case layoutMessage = "window.layout.message"
    case layoutCapturedName = "window.layout.capturedName"

    // 预设协调器
    case presetAlreadySet = "window.preset.alreadySet"
    case presetApplied = "window.preset.applied"
    case presetAppliedSkipped = "window.preset.appliedSkipped"
    case presetReplaceOne = "window.preset.replaceOne"
    case presetReplaceMany = "window.preset.replaceMany"
    case presetReplaceConfirm = "window.preset.replaceConfirm"
    case presetReplacementMessage = "window.preset.replacementMessage"
    case presetMore = "window.preset.more"

    // 自定义尺寸协调器
    case sizeDeleteMessage = "window.size.deleteMessage"

    static let table: [String: L10nEntry] = [
        WindowKey.fieldName.rawValue: L10nEntry("Name", "名称"),
        WindowKey.fieldSize.rawValue: L10nEntry("Size", "尺寸"),
        WindowKey.fieldOffset.rawValue: L10nEntry("Offset", "偏移"),
        WindowKey.fieldPosition.rawValue: L10nEntry("Position", "位置"),
        WindowKey.fieldWidth.rawValue: L10nEntry("Width", "宽度"),
        WindowKey.fieldHeight.rawValue: L10nEntry("Height", "高度"),
        WindowKey.fieldHorizontalOffset.rawValue: L10nEntry(
            "Horizontal offset", "水平偏移"),
        WindowKey.fieldVerticalOffset.rawValue: L10nEntry("Vertical offset", "垂直偏移"),
        WindowKey.actionEdit.rawValue: L10nEntry("Edit", "编辑"),
        WindowKey.actionDelete.rawValue: L10nEntry("Delete", "删除"),
        WindowKey.actionDuplicate.rawValue: L10nEntry("Duplicate", "复制"),
        WindowKey.actionCancel.rawValue: L10nEntry("Cancel", "取消"),
        WindowKey.actionSave.rawValue: L10nEntry("Save", "保存"),
        WindowKey.actionShowInLauncher.rawValue: L10nEntry(
            "Show %@ in launcher", "在启动器中显示 %@"),
        WindowKey.actionRun.rawValue: L10nEntry("Run %@", "运行 %@"),
        WindowKey.actionEnter.rawValue: L10nEntry("Enter %@", "进入 %@"),
        WindowKey.actionChooseWindows.rawValue: L10nEntry(
            "Choose windows for %@", "为 %@ 选择窗口"),
        WindowKey.deleteTitle.rawValue: L10nEntry("Delete “%@”?", "删除“%@”？"),
        WindowKey.permissionTitle.rawValue: L10nEntry(
            "GearMac Needs Accessibility Access", "GearMac 需要辅助功能权限"),
        WindowKey.permissionMessage.rawValue: L10nEntry(
            "Arranging windows uses the same permission as pasting.",
            "排列窗口与粘贴使用同一项权限。"),
        WindowKey.permissionRecovery.rawValue: L10nEntry("Open Settings", "打开设置"),

        WindowKey.summaryWindowOne.rawValue: L10nEntry("1 window", "1 个窗口"),
        WindowKey.summaryWindowMany.rawValue: L10nEntry("%d windows", "%d 个窗口"),
        WindowKey.summaryDisplays.rawValue: L10nEntry(
            "%1$@ · %2$d displays", "%1$@ · %2$d 台显示器"),
        WindowKey.sizeSummaryOffset.rawValue: L10nEntry(
            " · Offset %1$d, %2$d pt", " · 偏移 %1$d、%2$d pt"),
        WindowKey.skipDisplayOne.rawValue: L10nEntry(
            "1 display not connected", "1 台显示器未连接"),
        WindowKey.skipDisplayMany.rawValue: L10nEntry(
            "%d displays not connected", "%d 台显示器未连接"),
        WindowKey.skipEntryOne.rawValue: L10nEntry("1 entry skipped", "跳过 1 个条目"),
        WindowKey.skipEntryMany.rawValue: L10nEntry("%d entries skipped", "跳过 %d 个条目"),

        WindowKey.errorLayoutEmptyName.rawValue: L10nEntry(
            "Enter a name for the layout.", "请为布局输入名称。"),
        WindowKey.errorLayoutDuplicateName.rawValue: L10nEntry(
            "A window layout with this name already exists.", "已存在同名窗口布局。"),
        WindowKey.errorLayoutNoEntries.rawValue: L10nEntry(
            "Add at least one app to the layout.", "请至少向布局添加一个应用。"),
        WindowKey.errorNameNullCharacter.rawValue: L10nEntry(
            "Names cannot contain null characters.", "名称不能包含空字符。"),
        WindowKey.errorSizeEmptyName.rawValue: L10nEntry(
            "Enter a name for the size.", "请为尺寸输入名称。"),
        WindowKey.errorSizeDuplicateName.rawValue: L10nEntry(
            "A custom size with this name already exists.", "已存在同名自定义尺寸。"),
        WindowKey.errorRoomEmptyName.rawValue: L10nEntry(
            "Enter a name for the room.", "请为房间输入名称。"),
        WindowKey.errorRoomDuplicateName.rawValue: L10nEntry(
            "A room with this name already exists.", "已存在同名房间。"),
        WindowKey.errorRoomNoWindows.rawValue: L10nEntry(
            "Choose at least one window for the room.", "请为房间至少选择一个窗口。"),

        WindowKey.groupHalves.rawValue: L10nEntry("Halves", "半屏"),
        WindowKey.groupQuarters.rawValue: L10nEntry("Quarters", "四分之一"),
        WindowKey.groupFourths.rawValue: L10nEntry("Fourths", "四分之三"),
        WindowKey.groupThirds.rawValue: L10nEntry("Thirds", "三分之一"),
        WindowKey.groupSizing.rawValue: L10nEntry("Sizing", "尺寸"),
        WindowKey.groupMoving.rawValue: L10nEntry("Moving", "移动"),
        WindowKey.groupFullscreen.rawValue: L10nEntry("Fullscreen", "全屏"),
        WindowKey.groupSpaces.rawValue: L10nEntry("Spaces", "空间"),

        WindowKey.commandLeftHalf.rawValue: L10nEntry("Left Half", "左半屏"),
        WindowKey.commandRightHalf.rawValue: L10nEntry("Right Half", "右半屏"),
        WindowKey.commandTopHalf.rawValue: L10nEntry("Top Half", "上半屏"),
        WindowKey.commandBottomHalf.rawValue: L10nEntry("Bottom Half", "下半屏"),
        WindowKey.commandTopLeftQuarter.rawValue: L10nEntry(
            "Top Left Quarter", "左上四分之一"),
        WindowKey.commandTopRightQuarter.rawValue: L10nEntry(
            "Top Right Quarter", "右上四分之一"),
        WindowKey.commandBottomLeftQuarter.rawValue: L10nEntry(
            "Bottom Left Quarter", "左下四分之一"),
        WindowKey.commandBottomRightQuarter.rawValue: L10nEntry(
            "Bottom Right Quarter", "右下四分之一"),
        WindowKey.commandFirstThreeFourths.rawValue: L10nEntry(
            "First Three Fourths", "左侧四分之三"),
        WindowKey.commandLastThreeFourths.rawValue: L10nEntry(
            "Last Three Fourths", "右侧四分之三"),
        WindowKey.commandFirstThird.rawValue: L10nEntry("First Third", "左三分之一"),
        WindowKey.commandCenterThird.rawValue: L10nEntry("Center Third", "中间三分之一"),
        WindowKey.commandLastThird.rawValue: L10nEntry("Last Third", "右三分之一"),
        WindowKey.commandFirstTwoThirds.rawValue: L10nEntry(
            "First Two Thirds", "左三分之二"),
        WindowKey.commandLastTwoThirds.rawValue: L10nEntry("Last Two Thirds", "右三分之二"),
        WindowKey.commandMaximize.rawValue: L10nEntry("Maximize", "最大化"),
        WindowKey.commandAlmostMaximize.rawValue: L10nEntry(
            "Almost Maximize", "近似最大化"),
        WindowKey.commandReasonableSize.rawValue: L10nEntry("Reasonable Size", "合适大小"),
        WindowKey.commandMaximizeHeight.rawValue: L10nEntry(
            "Maximize Height", "最大化高度"),
        WindowKey.commandMaximizeWidth.rawValue: L10nEntry("Maximize Width", "最大化宽度"),
        WindowKey.commandCenter.rawValue: L10nEntry("Center", "居中"),
        WindowKey.commandCenterHalf.rawValue: L10nEntry("Center Half", "居中半屏"),
        WindowKey.commandCenterTwoThirds.rawValue: L10nEntry(
            "Center Two Thirds", "居中三分之二"),
        WindowKey.commandMakeLarger.rawValue: L10nEntry("Make Larger", "放大"),
        WindowKey.commandMakeSmaller.rawValue: L10nEntry("Make Smaller", "缩小"),
        WindowKey.commandRestore.rawValue: L10nEntry("Restore Window", "恢复窗口"),
        WindowKey.commandMoveLeft.rawValue: L10nEntry("Move Left", "左移"),
        WindowKey.commandMoveRight.rawValue: L10nEntry("Move Right", "右移"),
        WindowKey.commandMoveUp.rawValue: L10nEntry("Move Up", "上移"),
        WindowKey.commandMoveDown.rawValue: L10nEntry("Move Down", "下移"),
        WindowKey.commandNextDisplay.rawValue: L10nEntry(
            "Move to Next Display", "移到下一台显示器"),
        WindowKey.commandPreviousDisplay.rawValue: L10nEntry(
            "Move to Previous Display", "移到上一台显示器"),
        WindowKey.commandToggleFullscreen.rawValue: L10nEntry(
            "Toggle Fullscreen", "切换全屏"),
        WindowKey.commandPreviousSpace.rawValue: L10nEntry(
            "Switch to Previous Space", "切换到上一个空间"),
        WindowKey.commandNextSpace.rawValue: L10nEntry(
            "Switch to Next Space", "切换到下一个空间"),

        WindowKey.anchorTopLeft.rawValue: L10nEntry("Top Left", "左上"),
        WindowKey.anchorTop.rawValue: L10nEntry("Top", "上"),
        WindowKey.anchorTopRight.rawValue: L10nEntry("Top Right", "右上"),
        WindowKey.anchorLeft.rawValue: L10nEntry("Left", "左"),
        WindowKey.anchorCenter.rawValue: L10nEntry("Center", "居中"),
        WindowKey.anchorRight.rawValue: L10nEntry("Right", "右"),
        WindowKey.anchorBottomLeft.rawValue: L10nEntry("Bottom Left", "左下"),
        WindowKey.anchorBottom.rawValue: L10nEntry("Bottom", "下"),
        WindowKey.anchorBottomRight.rawValue: L10nEntry("Bottom Right", "右下"),

        WindowKey.cycleNone.rawValue: L10nEntry("None", "关闭"),
        WindowKey.cycleSizes.rawValue: L10nEntry(
            "Cycle ½, ⅓ and ⅔", "循环 ½、⅓ 与 ⅔"),
        WindowKey.cycleDisplays.rawValue: L10nEntry("Cycle displays", "循环切换显示器"),
        WindowKey.cycleNoneDetail.rawValue: L10nEntry(
            "Repeating a half keeps the same frame.", "重复按半屏快捷键时保持原样。"),
        WindowKey.cycleSizesDetail.rawValue: L10nEntry(
            "Repeating a half steps through ⅓ and ⅔.",
            "重复按半屏快捷键将在 ⅓ 与 ⅔ 之间步进。"),
        WindowKey.cycleDisplaysDetail.rawValue: L10nEntry(
            "Repeating a half moves it across your displays.",
            "重复按半屏快捷键会在各显示器之间移动。"),

        WindowKey.roomKindAuto.rawValue: L10nEntry("Auto", "自动"),
        WindowKey.roomKindFocus.rawValue: L10nEntry("Focus", "聚焦"),
        WindowKey.roomKindStack.rawValue: L10nEntry("Stack", "堆叠"),
        WindowKey.roomKindColumns.rawValue: L10nEntry("Columns", "分栏"),
        WindowKey.roomKindGrid.rawValue: L10nEntry("Grid", "网格"),
        WindowKey.roomKindCustom.rawValue: L10nEntry("Custom", "自定义"),
        WindowKey.roomKindSaved.rawValue: L10nEntry("As Arranged", "按现状"),

        WindowKey.presetRectangle.rawValue: L10nEntry(
            "Rectangle / Magnet", "Rectangle / Magnet"),
        WindowKey.presetSpectacle.rawValue: L10nEntry("Spectacle", "Spectacle"),

        WindowKey.settingsEnableTitle.rawValue: L10nEntry(
            "Enable window management", "启用窗口管理"),
        WindowKey.settingsEnableSubtitle.rawValue: L10nEntry(
            "Moves the last window you used. Needs Accessibility.",
            "移动你最近使用的窗口。需要辅助功能权限。"),
        WindowKey.settingsDeleteLayoutMessage.rawValue: L10nEntry(
            "Its global shortcut and launcher references go with it.",
            "它的全局快捷键与启动器引用也会一并删除。"),
        WindowKey.settingsCycling.rawValue: L10nEntry("Cycling", "循环"),
        WindowKey.settingsGap.rawValue: L10nEntry("Gap between windows", "窗口间距"),
        WindowKey.settingsGapDetail.rawValue: L10nEntry(
            "Between tiled windows and screen edges.", "平铺窗口之间以及与屏幕边缘之间的距离。"),
        WindowKey.settingsShortcutPreset.rawValue: L10nEntry("Shortcut preset", "快捷键预设"),
        WindowKey.settingsShortcutPresetDetail.rawValue: L10nEntry(
            "Fills in another app's shortcuts. Others stay as they are.",
            "填入其他应用的快捷键。其余保持不变。"),
        WindowKey.settingsChoose.rawValue: L10nEntry("Choose…", "选择…"),
        WindowKey.settingsApply.rawValue: L10nEntry("Apply", "应用"),

        WindowKey.layoutsShowInLauncher.rawValue: L10nEntry(
            "Show layouts in launcher", "在启动器中显示布局"),
        WindowKey.layoutsSearchPrompt.rawValue: L10nEntry("Search layouts…", "搜索布局…"),
        WindowKey.layoutsNew.rawValue: L10nEntry("New Layout", "新建布局"),
        WindowKey.layoutsCapture.rawValue: L10nEntry(
            "Create Layout from Current Windows", "从当前窗口创建布局"),
        WindowKey.layoutsEmpty.rawValue: L10nEntry(
            "Save an arrangement, then restore it with one shortcut.",
            "保存一组排布，随后用一个快捷键即可恢复。"),
        WindowKey.layoutsNoMatch.rawValue: L10nEntry(
            "No layout matches “%@”.", "没有布局匹配“%@”。"),

        WindowKey.roomsShowInLauncher.rawValue: L10nEntry(
            "Show rooms in launcher", "在启动器中显示房间"),
        WindowKey.roomsEmpty.rawValue: L10nEntry(
            "Save a project's windows as a room, then walk into it with one shortcut.",
            "把一个项目的窗口保存为房间，随后用一个快捷键即可进入。"),
        WindowKey.roomsNew.rawValue: L10nEntry("New Room", "新建房间"),
        WindowKey.roomsEnterHelp.rawValue: L10nEntry("Enter this room", "进入此房间"),
        WindowKey.roomsChooseHelp.rawValue: L10nEntry("Choose its windows", "选择它的窗口"),

        WindowKey.sizesNew.rawValue: L10nEntry("New Custom Size", "新建自定义尺寸"),

        WindowKey.editorCaptureTitle.rawValue: L10nEntry(
            "Capture Window Layout", "捕获窗口布局"),
        WindowKey.editorNewTitle.rawValue: L10nEntry("New Window Layout", "新建窗口布局"),
        WindowKey.editorEditTitle.rawValue: L10nEntry("Edit Window Layout", "编辑窗口布局"),
        WindowKey.inspectorSectionLayout.rawValue: L10nEntry("Layout", "布局"),
        WindowKey.inspectorNamePlaceholder.rawValue: L10nEntry("Office", "办公室"),
        WindowKey.inspectorChooseIcon.rawValue: L10nEntry("Choose an icon", "选择图标"),
        WindowKey.inspectorUsePreferredGap.rawValue: L10nEntry(
            "Use preferred gap", "使用首选间距"),
        WindowKey.inspectorUsePreferredGapDetail.rawValue: L10nEntry(
            "Inset every window by the gap set above, as the tiling commands do.",
            "按上方设置的间距内缩每个窗口，与平铺命令一致。"),
        WindowKey.inspectorBringToFront.rawValue: L10nEntry("Bring to front", "置于最前"),
        WindowKey.inspectorBringToFrontDetail.rawValue: L10nEntry(
            "Focus this window once the layout finishes. Only one window per layout.",
            "布局完成时聚焦此窗口。每份布局只允许一个。"),

        WindowKey.previewNoDisplay.rawValue: L10nEntry("No display selected", "未选择显示器"),
        WindowKey.previewDisplayNotConnected.rawValue: L10nEntry(
            "This display isn't connected.", "此显示器未连接。"),
        WindowKey.previewNotConnectedLabel.rawValue: L10nEntry(
            "Preview, display not connected", "预览，显示器未连接"),
        WindowKey.previewCaptionNotConnected.rawValue: L10nEntry(
            "%@ · not connected", "%@ · 未连接"),
        WindowKey.previewDescription.rawValue: L10nEntry(
            "Preview of %1$@, %2$@", "%1$@ 的预览，%2$@"),

        WindowKey.tabsDisplay.rawValue: L10nEntry("Display", "显示器"),
        WindowKey.tabsDisplayLabel.rawValue: L10nEntry(
            "Display %1$d, %2$@", "显示器 %1$d，%2$@"),

        WindowKey.argumentTitle.rawValue: L10nEntry("Argument", "参数"),
        WindowKey.argumentNone.rawValue: L10nEntry("None", "无"),
        WindowKey.argumentChooseFile.rawValue: L10nEntry("Choose File…", "选择文件…"),
        WindowKey.argumentChooseFolder.rawValue: L10nEntry("Choose Folder…", "选择文件夹…"),
        WindowKey.argumentEnterURL.rawValue: L10nEntry("Enter URL…", "输入 URL…"),
        WindowKey.argumentQuicklinks.rawValue: L10nEntry("Quicklinks", "快捷链接"),
        WindowKey.entryAddLabel.rawValue: L10nEntry(
            "Add an app to this layout", "向此布局添加应用"),
        WindowKey.entryNoApp.rawValue: L10nEntry("No app yet", "暂无应用"),
        WindowKey.entryEditingLabel.rawValue: L10nEntry(
            "Entry being edited", "正在编辑的条目"),
        WindowKey.entryRemove.rawValue: L10nEntry("Remove This Entry", "移除此条目"),

        WindowKey.sizeEditorEditTitle.rawValue: L10nEntry(
            "Edit Custom Size", "编辑自定义尺寸"),
        WindowKey.sizeEditorSubtitle.rawValue: L10nEntry(
            "Resizes the window you were last in, on the display it is already on.",
            "调整你最近所在窗口的大小，保持在其当前显示器上。"),
        WindowKey.sizeEditorNamePlaceholder.rawValue: L10nEntry("Wide Center", "宽屏居中"),
        WindowKey.sizeEditorUnit.rawValue: L10nEntry("%@ unit", "%@ 单位"),

        WindowKey.roomPickerAddTo.rawValue: L10nEntry("Add to %@", "添加到 %@"),
        WindowKey.roomPickerRemoveFrom.rawValue: L10nEntry("Remove from %@", "从 %@ 移除"),
        WindowKey.roomPickerSave.rawValue: L10nEntry("Save Room", "保存房间"),
        WindowKey.roomPickerReading.rawValue: L10nEntry(
            "Reading windows…", "正在读取窗口…"),
        WindowKey.roomPickerEmptyNoWindows.rawValue: L10nEntry(
            "No open windows — type an app's name to add it",
            "没有打开的窗口 — 输入应用名称以添加"),
        WindowKey.roomPickerEmptyNoMatch.rawValue: L10nEntry(
            "No windows or apps found", "未找到窗口或应用"),

        WindowKey.roomsScreenChooseWindows.rawValue: L10nEntry(
            "Choose Windows", "选择窗口"),
        WindowKey.roomsScreenCreateRoom.rawValue: L10nEntry("Create Room", "创建房间"),
        WindowKey.roomsScreenEnterRoom.rawValue: L10nEntry("Enter Room", "进入房间"),
        WindowKey.roomsScreenNextLayout.rawValue: L10nEntry("Next Layout", "下一个布局"),
        WindowKey.roomsScreenRemember.rawValue: L10nEntry(
            "Remember Arrangement", "记住排布"),
        WindowKey.roomsScreenChooseWindowsEllipsis.rawValue: L10nEntry(
            "Choose Windows…", "选择窗口…"),
        WindowKey.roomsScreenDeleteRoom.rawValue: L10nEntry("Delete Room", "删除房间"),
        WindowKey.roomsScreenEmpty.rawValue: L10nEntry(
            "Type a name to make your first room", "输入名称以创建第一个房间"),
        WindowKey.roomsListChooseWindowsFor.rawValue: L10nEntry(
            "Choose Windows for “%@”", "为“%@”选择窗口"),
        WindowKey.roomsListCreateRoomNamed.rawValue: L10nEntry(
            "Create Room “%@”", "创建房间“%@”"),
        WindowKey.roomsListCurrent.rawValue: L10nEntry("Current", "当前"),
        WindowKey.roomsListEditSubtitle.rawValue: L10nEntry(
            "Pick the open windows that belong in it", "选择应归入其中的已打开窗口"),
        WindowKey.roomsListAccessibilityLayout.rawValue: L10nEntry(
            "%1$@, %2$@ layout", "%1$@，%2$@ 布局"),
        WindowKey.pickerListHidden.rawValue: L10nEntry("%@ · Hidden", "%@ · 已隐藏"),
        WindowKey.pickerListMinimized.rawValue: L10nEntry("%@ · Minimized", "%@ · 已最小化"),
        WindowKey.pickerListAppOpensWithRoom.rawValue: L10nEntry(
            "App · Opens with the room", "应用 · 随房间一起打开"),
        WindowKey.pickerListAccessibilityPlace.rawValue: L10nEntry(
            "%1$@, number %2$d in the room", "%1$@，房间中第 %2$d 个"),

        WindowKey.roomOnlyOneLayout.rawValue: L10nEntry(
            "Only one layout fits these windows here",
            "这些窗口在当前显示器上只适合用一种布局"),
        WindowKey.roomNameMissing.rawValue: L10nEntry(
            "Type a name for the room first", "请先输入房间名称"),
        WindowKey.roomPickOne.rawValue: L10nEntry(
            "Pick at least one window or app for the room",
            "请为房间至少选择一个窗口或应用"),
        WindowKey.roomSaveFailed.rawValue: L10nEntry("Couldn't save the room", "无法保存房间"),
        WindowKey.roomNoneOpen.rawValue: L10nEntry(
            "None of %@’s windows are open", "%@ 的窗口都没有打开"),
        WindowKey.roomRemembered.rawValue: L10nEntry(
            "%1$@ — remembered as %2$@", "%1$@ — 已记忆为 %2$@"),
        WindowKey.roomDeleteMessage.rawValue: L10nEntry(
            "Its windows stay open. Its shortcut goes with it.",
            "它的窗口保持打开。它的快捷键会一并删除。"),
        WindowKey.roomEnterFailedTitle.rawValue: L10nEntry(
            "Couldn't Enter “%@”", "无法进入“%@”"),
        WindowKey.roomEnterFailedMessage.rawValue: L10nEntry(
            "None of its windows are open. Open them, then choose them again.",
            "它的窗口都没有打开。请打开后再重新选择。"),
        WindowKey.roomMissing.rawValue: L10nEntry(
            "%1$@ — %2$@ not open", "%1$@ — %2$@ 未打开"),
        WindowKey.roomPermissionMessage.rawValue: L10nEntry(
            "Rooms move and hide other apps' windows.",
            "房间会移动并隐藏其他应用的窗口。"),

        WindowKey.layoutNoWindowsToCapture.rawValue: L10nEntry(
            "No windows to capture", "没有可捕获的窗口"),
        WindowKey.layoutPermissionMessage.rawValue: L10nEntry(
            "Arranging windows uses the same permission as pasting.",
            "排列窗口与粘贴使用同一项权限。"),
        WindowKey.layoutRunFailedTitle.rawValue: L10nEntry(
            "Couldn't Run “%@”", "无法运行“%@”"),
        WindowKey.layoutSaveFailedTitle.rawValue: L10nEntry(
            "Couldn't Save the Layout", "无法保存布局"),
        WindowKey.layoutSaveFailedMessage.rawValue: L10nEntry(
            "The layout could not be saved.", "无法保存该布局。"),
        WindowKey.layoutMissingAppOne.rawValue: L10nEntry(
            "1 app didn't open", "1 个应用未打开"),
        WindowKey.layoutMissingAppMany.rawValue: L10nEntry(
            "%d apps didn't open", "%d 个应用未打开"),
        WindowKey.layoutFailedAppOne.rawValue: L10nEntry(
            "1 app couldn't open", "1 个应用无法打开"),
        WindowKey.layoutFailedAppMany.rawValue: L10nEntry(
            "%d apps couldn't open", "%d 个应用无法打开"),
        WindowKey.layoutMessage.rawValue: L10nEntry("%1$@ — %2$@", "%1$@ — %2$@"),
        WindowKey.layoutCapturedName.rawValue: L10nEntry("Captured Layout", "捕获的布局"),

        WindowKey.presetAlreadySet.rawValue: L10nEntry(
            "%@ shortcuts already set", "%@ 快捷键已设置"),
        WindowKey.presetApplied.rawValue: L10nEntry("Applied %@ shortcuts", "已应用 %@ 快捷键"),
        WindowKey.presetAppliedSkipped.rawValue: L10nEntry(
            "Applied %1$@ shortcuts — %2$d skipped, keys in use",
            "已应用 %1$@ 快捷键 — 跳过 %2$d 个，按键已被占用"),
        WindowKey.presetReplaceOne.rawValue: L10nEntry(
            "Replace 1 shortcut?", "替换 1 个快捷键？"),
        WindowKey.presetReplaceMany.rawValue: L10nEntry(
            "Replace %d shortcuts?", "替换 %d 个快捷键？"),
        WindowKey.presetReplaceConfirm.rawValue: L10nEntry("Replace", "替换"),
        WindowKey.presetReplacementMessage.rawValue: L10nEntry(
            "%1$@%2$@ will use the %3$@ keys instead of the ones you set.",
            "%1$@%2$@ 将改用 %3$@ 的按键，而不是你设置的按键。"),
        WindowKey.presetMore.rawValue: L10nEntry(" and %d more", "以及另外 %d 个"),

        WindowKey.sizeDeleteMessage.rawValue: L10nEntry(
            "Its shortcut and launcher references go with it.",
            "它的快捷键与启动器引用也会一并删除。"),
    ]
}
