// 文件职责：提供可选择已安装应用的可搜索浮层控件，并统一解析 bundle id 对应的名称与图标。
// 分层：UI（SwiftUI + AppKit 图标解析）；视图只展示，选择通过回调上抛。
import AppKit
import SwiftUI

/// 已安装应用的可搜索列表，数据取自启动器自身的索引。
struct AppPickerPopover: View {
    /// 需要排除的 bundle id——即已被选中的那些。
    var excluded: Set<String> = []
    /// 调用方可以清除选择时，显示在列表上方。
    var clearTitle: String?
    /// 回传 nil 表示用户点击了调用方提供的 `clearTitle` 行。
    let onSelect: (String?) -> Void

    @Environment(AppIndex.self) private var appIndex
    @Environment(AppSettings.self) private var settings
    @State private var query = ""

    /// 过滤出未被排除的应用条目，作为可选候选。
    private var candidates: [AppEntry] {
        (query.isEmpty ? appIndex.apps : appIndex.matches(query))
            .filter { $0.kind == .application }
            .filter { $0.bundleID.map { !excluded.contains($0) } ?? false }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField(settings.text(LauncherKey.searchApps), text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(Theme.Spacing.md)
            Divider()
            ScrollView {
                LazyVStack(spacing: 1) {
                    if let clearTitle, query.isEmpty {
                        row(title: clearTitle, icon: nil) { onSelect(nil) }
                    }
                    ForEach(candidates) { app in
                        row(title: app.name, icon: app.icon) {
                            if let id = app.bundleID { onSelect(id) }
                        }
                    }
                }
                .padding(Theme.Spacing.sm)
            }
        }
        .frame(width: 220, height: 240)
    }

    /// 渲染列表中的一行按钮（图标 + 标题）。
    private func row(title: String, icon: NSImage?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.lg) {
                Group {
                    if let icon {
                        Image(nsImage: icon).resizable()
                    } else {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .frame(width: 20, height: 20)
                Text(title)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// bundle id → 可展示内容：先查索引，再问 LaunchServices，最后用占位图标。
@MainActor
enum AppPresentation {
    /// 解析出该 bundle id 对应的展示名与图标。
    static func resolve(bundleID: String, in appIndex: AppIndex) -> (name: String, icon: NSImage) {
        IconCache.observeStyle()
        if let app = appIndex.apps.first(where: { $0.bundleID == bundleID }) {
            return (app.name, app.icon)
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return (url.deletingPathExtension().lastPathComponent, IconCache.icon(forFile: url.path))
        }
        return (bundleID, NSWorkspace.shared.icon(for: .applicationBundle))
    }
}
