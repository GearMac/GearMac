// 文件职责：功能页的数据源，定义 Feature/MinorFeature 类型与核心、次要功能清单。
// 分层：Model（静态数据）；每个条目对应源码中的真实功能，并链接到覆盖它的文档页。

import type { IconName } from "../components/ui/feature-icons";

// 功能卡片可选的内嵌预览类型，渲染组件按此枚举选择预览。
export type FeaturePreview =
  | "launcher"
  | "extensions"
  | "clipboard"
  | "calculator"
  | "aiChat"
  | "quickActions"
  | "windows"
  | "snippets";

// 一个核心功能的全部展示数据。
export type Feature = {
  icon: IconName;
  title: string;
  body: string;
  /** 指向覆盖该功能文档页的深链。 */
  href: string;
  preview: FeaturePreview;
  /** 宽屏下横跨 bento 的两列。 */
  isWide: boolean;
};

// 次要功能：只保留图标、标题与链接。
export type MinorFeature = Pick<Feature, "icon" | "title" | "href">;

// GearMac 的全部功能，用平实的语言描述。内容与 app 实际发布的一致 —— 每项都对应源码
// 中的真实功能，并链接到覆盖它的文档页。顺序决定 bento 布局：
// 每一行合计四列，宽卡片算两列。
export const coreFeatures: Feature[] = [
  {
    icon: "launch",
    title: "App launcher",
    body: "Find any app by typing a few letters and open it from the keyboard. Pin favorites, see what's running, and quit or restart apps.",
    href: "/docs/launcher",
    preview: "launcher",
    isWide: true,
  },
  {
    icon: "calculator",
    title: "Inline calculator",
    body: "Math, units, currencies, time zones, and dates like “days till 9 Apr”.",
    href: "/docs/features/calculator",
    preview: "calculator",
    isWide: false,
  },
  {
    icon: "clipboard",
    title: "Clipboard history",
    body: "Search the text, images, files and colors you've copied, then paste them back.",
    href: "/docs/features/clipboard",
    preview: "clipboard",
    isWide: false,
  },
  {
    icon: "aiChat",
    title: "AI Chat",
    body: "Use Apple Intelligence, Claude, Codex, Grok, OpenCode or your own API key.",
    href: "/docs/ai",
    preview: "aiChat",
    isWide: false,
  },
  {
    icon: "quickActions",
    title: "Quick Actions",
    body: "Select text in any app and fix, rewrite, translate or summarize it.",
    href: "/docs/ai/quick-actions",
    preview: "quickActions",
    isWide: false,
  },
  {
    icon: "windows",
    title: "Window management",
    body: "35 keyboard commands for halves, thirds, nudges and moving between displays, plus layouts you save.",
    href: "/docs/features/window-management",
    preview: "windows",
    isWide: true,
  },
  {
    icon: "extensions",
    title: "Raycast extensions",
    body: "Install them from the Raycast Store without Node or a build step. They run in JavaScriptCore and render in SwiftUI.",
    href: "/docs/extensions",
    preview: "extensions",
    isWide: true,
  },
  {
    icon: "snippets",
    title: "Snippets",
    body: "Type a keyword in any app and it expands into text. Snippets can use Markdown and placeholders.",
    href: "/docs/features/snippets",
    preview: "snippets",
    isWide: true,
  },
];

// 长尾功能：有名称、有链接，且不干扰上面的八个主功能。
export const moreFeatures: MinorFeature[] = [
  { icon: "notes", title: "Floating notes", href: "/docs/features/notes" },
  {
    icon: "fileSearch",
    title: "File search",
    href: "/docs/features/file-search",
  },
  {
    icon: "calendar",
    title: "Calendar & meetings",
    href: "/docs/features/calendar",
  },
  {
    icon: "navigation",
    title: "Window & menu search",
    href: "/docs/features/navigation",
  },
  {
    icon: "quicklinks",
    title: "Quicklinks",
    href: "/docs/launcher/quicklinks",
  },
  {
    icon: "keyboard",
    title: "Custom commands",
    href: "/docs/launcher/commands",
  },
  {
    icon: "bolt",
    title: "31 system actions",
    href: "/docs/launcher/system-actions",
  },
  { icon: "emoji", title: "Emoji & symbols", href: "/docs/features/emoji" },
  { icon: "globe", title: "Per-app hotkeys", href: "/docs/reference/hotkeys" },
  { icon: "hyper", title: "Hyper key", href: "/docs/reference/hotkeys" },
  { icon: "alias", title: "Aliases", href: "/docs/launcher/aliases" },
  {
    icon: "uninstall",
    title: "App uninstaller",
    href: "/docs/launcher/uninstall",
  },
  {
    icon: "inputSource",
    title: "Input source switching",
    href: "/docs/palette#input-source",
  },
  {
    icon: "appearance",
    title: "Light, Dark and glass",
    href: "/docs/palette#appearance",
  },
  { icon: "backup", title: "Backup & restore", href: "/docs/reference/backup" },
];
