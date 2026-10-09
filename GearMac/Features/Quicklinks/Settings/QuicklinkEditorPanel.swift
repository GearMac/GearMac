// 文件职责：提供单个 Quicklink 的「添加/编辑」面板视图，包含名称、链接、图标、打开方式与选项字段，以及占位符插入菜单。
// 分层：Settings/UI；SwiftUI 视图，读写经 AppCore 的 quicklinkCoordinator，不直接访问存储。
import AppKit
import SwiftUI

/// 标识要展示的编辑器；quicklink 为 nil 表示「添加」，UUID 用于区分两次打开。
struct QuicklinkEditRequest: Identifiable {
    let id = UUID()
    var quicklink: Quicklink?
}

/// 单个 Quicklink 的添加/编辑面板，由 Quicklinks 设置页展示。
struct QuicklinkEditorPanel: View {
    let quicklink: Quicklink?

    @Environment(\.settingsEditorDismiss) private var dismiss
    @Environment(AppIndex.self) private var appIndex
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    @State private var name: String
    @State private var link: String
    @State private var iconSymbol: String?
    @State private var openWithBundleID: String?
    @State private var showsInRootSearch: Bool
    @State private var isPinned: Bool
    @State private var errorMessage: String?
    @State private var showingAppPicker = false
    @State private var showingIconPicker = false

    /// 以现有 Quicklink 预填表单，传入 nil 时为空表单。
    init(quicklink: Quicklink?) {
        self.quicklink = quicklink
        _name = State(initialValue: quicklink?.name ?? "")
        _link = State(initialValue: quicklink?.link ?? "")
        _iconSymbol = State(initialValue: quicklink?.iconSymbol)
        _openWithBundleID = State(initialValue: quicklink?.openWithBundleID)
        _showsInRootSearch = State(initialValue: quicklink?.showsInRootSearch ?? true)
        _isPinned = State(initialValue: quicklink?.isPinned ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            SettingsEditorHeader(
                title: settings.text(
                    quicklink == nil ? QuicklinksKey.editorAddTitle : QuicklinksKey.editorEditTitle))

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(settings.text(QuicklinksKey.editorName))
                    .font(.callout.weight(.medium))
                TextField(settings.text(QuicklinksKey.editorNamePlaceholder), text: $name)
                    .settingsEditorTextField()
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    Text(settings.text(QuicklinksKey.editorLink))
                        .font(.callout.weight(.medium))
                    Spacer()
                    insertMenu
                }
                TextField(settings.text(QuicklinksKey.editorLinkPlaceholder), text: $link)
                    .settingsEditorTextField()
                    .font(.body.monospaced())
                destinationPreview
            }

            HStack(spacing: Theme.Spacing.xl) {
                iconField
                openWithField
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                optionToggle(
                    settings.text(QuicklinksKey.editorShowInRootSearch), isOn: $showsInRootSearch,
                    detail: settings.text(QuicklinksKey.editorShowInRootSearchDetail))
                optionToggle(
                    settings.text(QuicklinksKey.editorPinToTop), isOn: $isPinned,
                    detail: settings.text(QuicklinksKey.editorPinToTopDetail))
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack(spacing: Theme.Spacing.md) {
                Button(settings.text(QuicklinksKey.cancel)) { dismiss() }
                    .buttonStyle(.modalAction(.cancel))
                    .keyboardShortcut(.cancelAction)
                Button(settings.text(QuicklinksKey.save), action: save)
                    .buttonStyle(.modalAction(.primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed(name).isEmpty || trimmed(link).isEmpty)
            }
        }
        .padding(Theme.Spacing.dialogInset)
        .frame(width: Theme.Size.editorSheetWidth)
        .settingsEditorPanelSurface()
    }

    // MARK: - Fields

    /// 目标将如何被打开：这是模板化链接能给出的全部反馈。
    @ViewBuilder
    private var destinationPreview: some View {
        let value = trimmed(link)
        if value.isEmpty {
            EmptyView()
        } else if QuicklinkDestination.containsPlaceholder(value) {
            Text(settings.text(QuicklinksKey.editorResolvedHint))
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let destination = QuicklinkDestination.detect(value) {
            Label(destination.displayText, systemImage: destination.defaultSymbol)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        } else {
            Text(settings.text(QuicklinksKey.editorInvalidLink))
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    /// 仅包含在目标中有意义的占位符；`{cursor}` 与 `{snippet:…}` 仍按字面处理。
    private var insertMenu: some View {
        Menu(settings.text(QuicklinksKey.editorInsert)) {
            Button(settings.text(QuicklinksKey.editorArgument)) { insert("{argument}") }
            Button(settings.text(QuicklinksKey.editorNamedArgument)) {
                insert("{argument name=\"Query\"}")
            }
            Divider()
            Button(settings.text(QuicklinksKey.editorClipboard)) { insert("{clipboard}") }
            Button(settings.text(QuicklinksKey.editorSelectedText)) { insert("{selection}") }
            Divider()
            Button(settings.text(QuicklinksKey.editorDate)) { insert("{date}") }
            Button(settings.text(QuicklinksKey.editorTime)) { insert("{time}") }
            Button(settings.text(QuicklinksKey.editorDateTime)) { insert("{datetime}") }
            Button(settings.text(QuicklinksKey.editorCustomDateFormat)) {
                insert("{date format=\"yyyy-MM-dd\"}")
            }
            Divider()
            Button(settings.text(QuicklinksKey.editorUUID)) { insert("{uuid}") }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    /// 图标选择器提供的候选 SF Symbol 列表。
    private static let iconSymbols = [
        "globe", "folder", "doc.text", "link", "star", "bookmark", "magnifyingglass", "cart",
        "envelope", "message", "calendar", "clock", "checklist", "chart.bar", "hammer", "wrench",
        "ladybug", "terminal", "chevron.left.forwardslash.chevron.right", "cloud", "server.rack",
        "lock", "person.2", "building.2", "graduationcap", "book", "music.note", "play.rectangle",
        "photo", "paintbrush", "creditcard", "map"
    ]

    /// 图标选择字段，默认使用自动推断的图标。
    private var iconField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(settings.text(QuicklinksKey.editorIcon))
                .font(.callout.weight(.medium))
            Button {
                showingIconPicker = true
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    SymbolImage(name: resolvedSymbol, size: 14)
                    Text(
                        settings.text(
                            iconSymbol == nil
                                ? QuicklinksKey.editorAutomatic : QuicklinksKey.editorCustom)
                    )
                    .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(width: 150)
            }
            .popover(isPresented: $showingIconPicker, arrowEdge: .bottom) {
                SymbolPicker(
                    selection: $iconSymbol, fallback: automaticSymbol, symbols: Self.iconSymbols
                ) {
                    showingIconPicker = false
                }
            }
        }
    }

    /// 打开方式字段，默认使用系统默认应用。
    private var openWithField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(settings.text(QuicklinksKey.editorOpenWith))
                .font(.callout.weight(.medium))
            Button {
                showingAppPicker = true
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    if let openWithBundleID {
                        let app = AppPresentation.resolve(bundleID: openWithBundleID, in: appIndex)
                        Image(nsImage: app.icon).resizable().frame(width: 16, height: 16)
                        Text(app.name).lineLimit(1)
                    } else {
                        Text(settings.text(QuicklinksKey.editorDefaultApp))
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: 180)
            }
            .popover(isPresented: $showingAppPicker, arrowEdge: .bottom) {
                AppPickerPopover(clearTitle: settings.text(QuicklinksKey.editorDefaultApp)) { bundleID in
                    openWithBundleID = bundleID
                    showingAppPicker = false
                }
            }
        }
    }

    /// 构建设置项复选框（标题 + 说明）。
    private func optionToggle(_ title: String, isOn: Binding<Bool>, detail: String) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.checkbox)
    }

    // MARK: - Behaviour

    /// 根据链接目标推断出的默认图标。
    private var automaticSymbol: String {
        QuicklinkDestination.detect(trimmed(link))?.defaultSymbol ?? Quicklink.sfSymbol
    }

    /// 最终使用的图标：自定义优先，否则自动推断。
    private var resolvedSymbol: String { iconSymbol ?? automaticSymbol }

    /// 将占位符追加到链接末尾。
    private func insert(_ token: String) {
        link += token
    }

    /// 去除字符串首尾空白。
    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 校验并保存表单：新建或更新 Quicklink，失败时展示错误。
    private func save() {
        // 编辑时保留 UUID，从而保留该 Quicklink 的快捷键、收藏与可见性设置。
        let existing = quicklink
        let draft = Quicklink(
            id: existing?.id ?? UUID(), name: name, link: link,
            openWithBundleID: openWithBundleID, iconSymbol: iconSymbol,
            // 启用开关由列表行管理；编辑时沿用原值而非重置。
            isEnabled: existing?.isEnabled ?? true,
            showsInRootSearch: showsInRootSearch,
            // 重新置顶保留原始时间戳，因此保存编辑不会改变行的排序位置。
            pinnedAt: isPinned ? (existing?.pinnedAt ?? Date()) : nil,
            createdAt: existing?.createdAt ?? Date())
        do {
            if existing == nil {
                try core.quicklinkCoordinator.addQuicklink(draft)
            } else {
                try core.quicklinkCoordinator.updateQuicklink(draft)
            }
            dismiss()
        } catch let error as QuicklinkError {
            errorMessage = error.message(settings.language)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// 一个固定的小型网格而非符号浏览器；「自动」排在最前，因为它是更好的默认选择。
