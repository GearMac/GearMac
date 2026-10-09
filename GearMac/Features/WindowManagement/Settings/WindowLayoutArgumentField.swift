// 文件职责：布局编辑器中的参数（Argument）选择行，支持无、文件、文件夹、URL 与用户的快捷链接。
// 分层：UI（SwiftUI 设置控件）；选择结果直接写入 WindowLayoutDraft，不自行落盘。
import AppKit
import SwiftUI

/// 参数行：无、文件、文件夹、URL，或用户的某个快捷链接。
struct WindowLayoutArgumentField: View {
    let draft: WindowLayoutDraft

    @Environment(QuicklinkStore.self) private var quicklinks
    @Environment(AppSettings.self) private var settings
    @State private var isEditingURL = false
    @State private var urlText = ""
    @FocusState private var isURLFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(settings.text(WindowKey.argumentTitle))
                .font(.callout.weight(.medium))
            menu
            if isEditingURL {
                TextField("https://example.com", text: $urlText)
                    .textFieldStyle(.plain)
                    .focused($isURLFocused)
                    .focusEffectDisabled()
                    .layoutFieldChrome(isFocused: isURLFocused)
                    // 与数字字段同理需实时生效：⌘↵ 保存时不会让该字段失焦。
                    .onChange(of: urlText) { _, typed in draft.setArgument(typed) }
            }
        }
    }

    private var menu: some View {
        Menu {
            Button(settings.text(WindowKey.argumentNone)) { clear() }
            Button(settings.text(WindowKey.argumentChooseFile)) { choose(directories: false) }
            Button(settings.text(WindowKey.argumentChooseFolder)) { choose(directories: true) }
            Button(settings.text(WindowKey.argumentEnterURL)) {
                urlText = draft.selectedEntry?.argument ?? ""
                isEditingURL = true
            }
            if !quicklinks.quicklinks.isEmpty {
                // 复制而非引用：一次运行是单次执行，没有时机再提示占位符。
                Section(settings.text(WindowKey.argumentQuicklinks)) {
                    ForEach(quicklinks.quicklinks) { quicklink in
                        Button(quicklink.name) {
                            isEditingURL = false
                            draft.setArgument(quicklink.link)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                if let argument = draft.selectedEntry?.argument,
                    let destination = QuicklinkDestination.detect(argument)
                {
                    Image(systemName: destination.defaultSymbol)
                    Text(destination.displayText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text(settings.text(WindowKey.argumentNone)).foregroundStyle(.secondary)
                }
                Spacer(minLength: Theme.Spacing.sm)
                Image(systemName: "chevron.down")
                    .font(Theme.Typography.disclosure)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .layoutFieldChrome()
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    /// 清空选择：退出 URL 编辑态并移除参数。
    private func clear() {
        isEditingURL = false
        urlText = ""
        draft.setArgument(nil)
    }

    /// 弹出打开面板选择文件或文件夹，并把结果转为带 ~ 缩写的路径写入草稿。
    private func choose(directories: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = !directories
        panel.canChooseDirectories = directories
        panel.allowsMultipleSelection = false
        // 缺少这句时，附件型应用的打开面板会落在最前应用之后。
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isEditingURL = false
        draft.setArgument((url.path as NSString).abbreviatingWithTildeInPath)
    }
}
