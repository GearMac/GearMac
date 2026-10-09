// 文件职责：片段的启动器列表与预览：左侧结果行列表，右侧展示片段原始模板与信息区。
// 分层：UI；只渲染传入的数据并向上回调，不直接访问存储或系统能力。
import SwiftUI

/// 片段搜索结果列表，支持单击选中、双击激活与右键菜单。
struct SnippetsList: View {

    @Environment(\.metrics) private var metrics
    let results: [StoredSnippet]
    let selectedID: StoredSnippet.ID?
    let scroll: ScrollIntent
    let onSelect: (StoredSnippet) -> Void
    let onActivate: () -> Void
    let onActions: (StoredSnippet) -> Void

    /// 选中项是否为第一行，用于滚动定位到起始位置。
    private var firstRowSelected: Bool {
        selectedID != nil && selectedID == results.first?.id
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(results) { record in
                        SnippetRow(record: record, selected: record.id == selectedID)
                            .selectionFrame(record.id == selectedID)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(record) }
                            .simultaneousGesture(
                                TapGesture(count: 2).onEnded {
                                    onSelect(record)
                                    onActivate()
                                }
                            )
                            .onRightClick { onActions(record) }
                    }
                }
                .padding(.horizontal, metrics.spacing.md)
                .padding(.top, metrics.spacing.xs)
                .padding(.bottom, metrics.spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .scrollFollowsSelection(
                scroll, row: selectedID, atOrigin: firstRowSelected, proxy: proxy)
        }
    }
}

/// 单个片段结果行：图标、名称、关键字与快捷键提示。
private struct SnippetRow: View {

    @Environment(\.metrics) private var metrics
    @Environment(HotKeyManager.self) private var hotKeys
    let record: StoredSnippet
    let selected: Bool
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        IconCache.observeStyle()
        return HStack(spacing: metrics.spacing.lg) {
            Image(nsImage: IconCache.symbolIcon(named: "curlybraces")).resizable()
                .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
            Text(record.snippet.name)
                .font(metrics.typography.rowTitle)
                .lineLimit(1)
            Spacer(minLength: metrics.spacing.lg)
            if let keyword = record.snippet.keyword, !keyword.isEmpty {
                Text(keyword)
                    .font(metrics.typography.keyCap)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
            }
            if let keycaps = hotKeys.binding(for: .snippet(id: record.id))?.keycaps {
                HStack(spacing: metrics.spacing.xxs) {
                    ForEach(Array(keycaps.enumerated()), id: \.offset) { _, cap in
                        KeyCapChip(text: cap, style: .outline)
                    }
                }
            }
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous).fill(fill)
        )
        .armedHover($hovered)
    }
}

/// 片段预览：展示原始模板文本与信息区，避免展开带来的副作用。
struct SnippetPreview: View {
    let record: StoredSnippet?

    var body: some View {
        if let record {
            VStack(alignment: .leading, spacing: 0) {
                // 这里展示原始模板：若在此展开，每次按方向键都会读取剪贴板。
                ScrollView {
                    Text(record.snippet.text)
                        .font(.system(.subheadline, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                SnippetInfoSection(record: record)
            }
            .padding(.horizontal, 12)
        } else {
            Color.clear
        }
    }
}

/// “Information” 区块；其中数据都已在内存中，无需在主线程外收集。
private struct SnippetInfoSection: View {
    @Environment(\.metrics) private var metrics
    @Environment(HotKeyManager.self) private var hotKeys
    @Environment(AppSettings.self) private var settings
    let record: StoredSnippet

    private struct InfoRow: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    /// 信息区展示的行：名称、关键字、快捷键、文件名与字符数。
    private var rows: [InfoRow] {
        var rows = [InfoRow(label: settings.text(SnippetsKey.infoName), value: record.snippet.name)]
        if let keyword = record.snippet.keyword, !keyword.isEmpty {
            rows.append(InfoRow(label: settings.text(SnippetsKey.infoKeyword), value: keyword))
        }
        if let keycaps = hotKeys.binding(for: .snippet(id: record.id))?.keycaps {
            rows.append(InfoRow(label: settings.text(SnippetsKey.infoShortcut), value: keycaps.joined()))
        }
        rows.append(
            InfoRow(
                label: settings.text(SnippetsKey.infoFile),
                value: record.fileURL.lastPathComponent))
        rows.append(
            InfoRow(
                label: settings.text(SnippetsKey.infoCharacters),
                value: record.snippet.text.count.formatted()))
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.sm) {
            Text(settings.text(SnippetsKey.infoTitle))
                .font(metrics.typography.sectionHeader)
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                let rows = self.rows
                ForEach(rows) { row in
                    if row.id != rows.first?.id { Divider() }
                    HStack(spacing: metrics.spacing.sm) {
                        Text(row.label).foregroundStyle(.secondary)
                        Spacer(minLength: metrics.spacing.lg)
                        Text(row.value).lineLimit(1).truncationMode(.middle)
                    }
                    .font(metrics.typography.keyCap)
                    .padding(.vertical, metrics.spacing.xs)
                }
            }
        }
        .padding(.vertical, metrics.spacing.md)
    }
}
