// 文件职责：表情设置页，提供列数选择、默认肤色等选项，并接入命令区。
// 分层：Settings；只读写 AppSettings，不直接操作表情存储。
import SwiftUI

/// 表情类设置的面板：命令、列数与默认肤色。
struct EmojiSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        return Form {
            FeatureCommandsSection(owner: .emoji, anchor: .emojiCommands)

            Section {
                EmojiColumnCountPicker(selection: $settings.emojiGridColumns)
                SettingsRow(
                    title: settings.text(EmojiKey.settingsSkinTone), anchor: .emojiAppearance
                ) {
                    HStack(spacing: Theme.Spacing.xs) {
                        ForEach(EmojiSkinTone.allCases) { tone in
                            let selected = settings.emojiSkinTone == tone
                            Button {
                                settings.emojiSkinTone = tone
                            } label: {
                                Text(tone.sample)
                                    .font(.system(size: Theme.Size.emojiSkinToneGlyph))
                                    .settingsOptionSegment(isSelected: selected)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(tone.localizedTitle(settings.language))
                            .accessibilityAddTraits(selected ? [.isSelected] : [])
                            .help(tone.localizedTitle(settings.language))
                        }
                    }
                }
            } header: {
                SettingsSectionHeader(.emojiAppearance)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.emoji)
    }
}

/// 五个预览让选择器的起始密度在用户打开面板前就能看出。
private struct EmojiColumnCountPicker: View {
    @Environment(AppSettings.self) private var settings
    @Binding var selection: EmojiGridColumns

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            SettingsRowTitle(.emojiAppearance, settings.text(EmojiKey.settingsColumnCount))

            HStack(spacing: Theme.Spacing.xl) {
                ForEach(EmojiGridColumns.allCases) { columns in
                    option(columns)
                }
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    /// 单个列数选项按钮：点选后写回绑定值。
    private func option(_ columns: EmojiGridColumns) -> some View {
        let isSelected = selection == columns
        return Button {
            selection = columns
        } label: {
            VStack(spacing: Theme.Spacing.sm) {
                EmojiColumnCountPreview(columns: columns.rawValue, isSelected: isSelected)
                Text(columns.rawValue, format: .number)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            String(
                format: settings.text(EmojiKey.settingsColumnsAccessibilityFormat),
                columns.rawValue))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// 列数的点阵缩略图，使用固定行列数的网格表现单元格密度。
private struct EmojiColumnCountPreview: View {
    let columns: Int
    let isSelected: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        EmojiGridDots(columns: columns)
            .fill(isSelected ? Theme.Colors.textTertiary : Theme.Colors.border)
            .background(
                shape.fill(isSelected ? Theme.Colors.controlSurface : Color.clear)
            )
            .overlay(
                shape.strokeBorder(
                    isSelected ? Theme.Colors.border : Theme.Colors.cardStroke,
                    lineWidth: Theme.Size.hairline)
            )
            .clipShape(shape)
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: Theme.Size.emojiSettingsGridPreview)
    }
}

/// 点阵共用同一套网格，使横向与纵向点列交在完全相同的点上。
private struct EmojiGridDots: Shape {
    let columns: Int

    private static let pointsPerCell = 4
    /// 与描边保持相同的栅格权重；同样的透明下亚像素圆会显得更淡。
    private static let dotDiameter = Theme.Size.hairline

    /// 绘制单元格边界上的圆点：横向与纵向的格线交点。
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let subdivisions = columns * Self.pointsPerCell
        guard subdivisions > 0 else { return path }
        let horizontalStep = rect.width / CGFloat(subdivisions)
        let verticalStep = rect.height / CGFloat(subdivisions)
        let radius = Self.dotDiameter / 2

        for row in 0...subdivisions {
            for column in 0...subdivisions {
                let onVertical =
                    column.isMultiple(of: Self.pointsPerCell)
                    && column > 0 && column < subdivisions
                let onHorizontal =
                    row.isMultiple(of: Self.pointsPerCell)
                    && row > 0 && row < subdivisions
                guard onVertical || onHorizontal else { continue }
                let center = CGPoint(
                    x: rect.minX + CGFloat(column) * horizontalStep,
                    y: rect.minY + CGFloat(row) * verticalStep)
                path.addEllipse(
                    in: CGRect(
                        x: center.x - radius, y: center.y - radius,
                        width: Self.dotDiameter, height: Self.dotDiameter))
            }
        }
        return path
    }
}
