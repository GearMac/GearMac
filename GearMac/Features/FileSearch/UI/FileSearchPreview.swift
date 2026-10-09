// 文件职责：结果列表右侧的预览面板：上方渲染文件本体，下方展示名称、位置、类型、大小与时间等元数据。
// 分层：UI；SwiftUI 视图，磁盘读取在后台执行。
import SwiftUI

/// 结果列表旁的预览面板：上方是文件本体，下方是文件系统提供的元数据。
struct FileSearchPreview: View {

    @Environment(\.metrics) private var metrics
    let result: FileSearchResult?

    var body: some View {
        if let result {
            VStack(alignment: .leading, spacing: 0) {
                // 先确定其尺寸，下方区块在剩余空间内滚动。
                FileSearchPreviewStage(result: result)
                    .aspectRatio(Theme.Size.previewAspectRatio, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .layoutPriority(1)
                ScrollView {
                    FileSearchInfoSection(result: result)
                }
            }
            .padding(.horizontal, metrics.spacing.xl)
        } else {
            Color.clear
        }
    }
}

/// 文件本体。跨选中项保持单一的视图实例：QuickLook 切换内容约需 8 毫秒。
private struct FileSearchPreviewStage: View {

    @Environment(\.metrics) private var metrics
    @Environment(PaletteState.self) private var palette
    let result: FileSearchResult

    private var card: RoundedRectangle {
        RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous)
    }

    var body: some View {
        stage
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, metrics.spacing.xl)
    }

    /// 卸载即是销毁：被移出窗口层级的面板会保留其视图树，因此用 overlay 隐藏它。
    @ViewBuilder private var stage: some View {
        if result.isDirectory {
            Image(systemName: "folder")
                .font(.system(.largeTitle))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tertiary)
        } else if palette.isVisible, !palette.fileSearchQuickLook {
            FileSearchSurface(url: result.url)
                .clipShape(card)
                .overlay(card.strokeBorder(Theme.Colors.cardStroke, lineWidth: 1))
        } else {
            Color.clear
        }
    }
}

/// 「Information」信息区；所有磁盘读取在非主线程上一次性完成。
private struct FileSearchInfoSection: View {

    @Environment(\.metrics) private var metrics
    @Environment(AppSettings.self) private var settings
    let result: FileSearchResult
    @State private var details = Details()

    /// 信息行所需的数据快照。
    private struct Details: Equatable, Sendable {
        var typeName: String?
        var bytes: Int?
        var created: Date?
        var modified: Date?
    }

    /// 一行标签与取值。
    private struct InfoRow: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    /// 相对日期加时间；共用同一实例，因为构建 `DateFormatter` 开销较大。
    @MainActor private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    /// 信息区的视图内容。
    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.sm) {
            Text(settings.text(FileSearchKey.previewInformation))
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
        .task(id: result.id) { await loadDetails() }
    }

    /// 组装展示用的信息行，按已有数据有条件地追加。
    private var rows: [InfoRow] {
        var rows = [
            InfoRow(label: settings.text(FileSearchKey.infoName), value: result.name),
            InfoRow(label: settings.text(FileSearchKey.infoWhere), value: result.parentPath),
            InfoRow(
                label: settings.text(FileSearchKey.infoType),
                value: details.typeName
                    ?? settings.text(
                        result.isDirectory ? FileSearchKey.infoFolder : FileSearchKey.infoFile))
        ]
        if let bytes = details.bytes {
            rows.append(
                InfoRow(
                    label: settings.text(FileSearchKey.infoSize),
                    value: Int64(bytes).formatted(.byteCount(style: .file))))
        }
        if let created = details.created {
            rows.append(
                InfoRow(
                    label: settings.text(FileSearchKey.infoCreated),
                    value: Self.stampFormatter.string(from: created)))
        }
        if let modified = details.modified {
            rows.append(
                InfoRow(
                    label: settings.text(FileSearchKey.infoModified),
                    value: Self.stampFormatter.string(from: modified)))
        }
        return rows
    }

    /// 类型数据库把文件夹写作 "folder"；Type 行读起来应与 Finder 的「种类」一致。
    private nonisolated static func sentenceCased(_ name: String) -> String {
        name.prefix(1).localizedUppercase + name.dropFirst()
    }

    /// 在后台读取该文件的大小与时间等元数据。
    private func loadDetails() async {
        // 先清空：上一个文件的大小不能留在当前文件名下。
        details = Details()
        let url = result.url
        let isDirectory = result.isDirectory
        details = await Task.detached(priority: .userInitiated) {
            let values = try? url.resourceValues(forKeys: [
                .contentTypeKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey
            ])
            return Details(
                typeName: values?.contentType?.localizedDescription.map(Self.sentenceCased),
                // 文件夹自身记录只有几字节，这不是该行想表达的大小。
                bytes: isDirectory ? nil : values?.fileSize,
                created: values?.creationDate,
                modified: values?.contentModificationDate)
        }.value
    }
}
