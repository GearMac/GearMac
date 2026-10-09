// 文件职责：渲染「排除的应用」列表与整段区块，并托管「添加应用」浮层选择器。
// 分层：UI（SwiftUI）；仅编辑传入的 bundle id 绑定，不直接读写存储。
import SwiftUI

/// 排除应用控件：每个排除项一行，而后是添加新排除项的选择器。标题由调用方负责，
/// 因此面板可以把该列表放到它所服务的命令旁边。
struct DisabledApplicationsList: View {
    @Binding var bundleIDs: [String]

    @Environment(AppSettings.self) private var settings
    @State private var picking = false

    var body: some View {
        ForEach(bundleIDs, id: \.self) { bundleID in
            DisabledAppRow(bundleID: bundleID) {
                bundleIDs.removeAll { $0 == bundleID }
            }
        }

        Button(settings.text(LauncherKey.addApplication)) { picking = true }
            .popover(isPresented: $picking, arrowEdge: .bottom) {
                AppPickerPopover(excluded: Set(bundleIDs)) { bundleID in
                    if let bundleID { bundleIDs.append(bundleID) }
                    picking = false
                }
            }
    }
}

/// 把排除列表整体作为一个 Section，用于排除项本身即为主题的面板。
struct DisabledApplicationsSection: View {
    @Binding var bundleIDs: [String]
    let anchor: SettingsAnchor
    let footer: String

    var body: some View {
        Section {
            DisabledApplicationsList(bundleIDs: $bundleIDs)
        } header: {
            SettingsSectionHeader(anchor)
        } footer: {
            Text(footer)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// 单个被排除的应用；只存储 bundle id，名称与图标在渲染时即时解析。
private struct DisabledAppRow: View {
    let bundleID: String
    let onRemove: () -> Void

    @Environment(AppIndex.self) private var appIndex
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let (name, icon) = AppPresentation.resolve(bundleID: bundleID, in: appIndex)
        LabeledContent {
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(format: settings.text(LauncherKey.stopExcludingFormat), name))
        } label: {
            Label {
                Text(name).lineLimit(1)
            } icon: {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: SettingsListMetrics.iconSize, height: SettingsListMetrics.iconSize)
            }
        }
    }
}
