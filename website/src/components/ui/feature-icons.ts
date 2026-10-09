// 文件职责：把功能名映射到 lucide-react 图标的共享表，供 data 目录按名字引用。
// 分层：UI 资源映射；功能卡片按名字取图标，其余组件直接 import lucide。

import {
  AppWindow,
  Archive,
  Calculator,
  CalendarDays,
  ClipboardList,
  FileSearch,
  Globe,
  Keyboard,
  Languages,
  Link2,
  MessagesSquare,
  NotebookPen,
  Puzzle,
  Search,
  Smile,
  Sparkles,
  SquareTerminal,
  Sun,
  Tag,
  Trash2,
  WandSparkles,
  LayoutGrid,
  Zap,
  type LucideIcon,
} from "lucide-react";

// 通用字形来自 lucide-react。功能卡片从 data 目录按名字引用这些映射；其余地方直接 import lucide。
export const featureIcons = {
  launch: Search,
  extensions: Puzzle,
  calculator: Calculator,
  clipboard: ClipboardList,
  snippets: SquareTerminal,
  notes: NotebookPen,
  fileSearch: FileSearch,
  quicklinks: Link2,
  windows: LayoutGrid,
  emoji: Smile,
  globe: Globe,
  bolt: Zap,
  hyper: Sparkles,
  backup: Archive,
  alias: Tag,
  uninstall: Trash2,
  inputSource: Languages,
  appearance: Sun,
  keyboard: Keyboard,
  aiChat: MessagesSquare,
  quickActions: WandSparkles,
  calendar: CalendarDays,
  navigation: AppWindow,
} satisfies Record<string, LucideIcon>;

// 功能图标名，即 featureIcons 的键集合，供 Feature 类型引用。
export type IconName = keyof typeof featureIcons;
