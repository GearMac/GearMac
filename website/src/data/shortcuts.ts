// 文件职责：快捷键速查表的数据源，是 docs/reference/shortcuts.md 的子集。
// 分层：Model（静态数据）；第一行是用户自行设置的组合键，GearMac 不预置，因此标注为“由你选择”。

export type ShortcutRow = { keys: string[]; does: string };

// 快捷键行，顺序即页面上的展示顺序。
export const shortcutRows: ShortcutRow[] = [
  { keys: ["⌥", "Space"], does: "Open the palette (you choose the keys)" },
  { keys: ["return"], does: "Run the main action" },
  { keys: ["⌘", "return"], does: "Run the second action" },
  { keys: ["⌘", "K"], does: "Open the actions menu" },
  { keys: ["tab"], does: "Switch between launcher, AI Chat and clipboard" },
  { keys: ["⌘", "1…0"], does: "Open favorite 1 to 10" },
  { keys: ["esc"], does: "Clear the search, go back, or close" },
  { keys: ["⌘", "esc"], does: "Back to the root search from anywhere" },
];
