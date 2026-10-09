// 文件职责：首屏演示面板的模拟数据，包含查询词、动作名与演示分组。
// 分层：Model（静态演示数据）；标签照抄真实应用的字符串（动作栏、小节标题、占位符），
// 每一行只使用 GearMac 自有条目或通用应用，不冒充任何人的真实数据。

export type DemoRowIcon =
  "ghost" | "hammer" | "shield" | "gem" | "orbit" | "audio";

// 演示行可用的图标键。
export type DemoRow = {
  title: string;
  kind: string;
  icon: DemoRowIcon;
  /** 应用图标的 CSS 背景。 */
  tint: string;
  /** 该行绑定的快捷键，在标题旁以键帽形式绘制。 */
  hotkey?: string[];
};

// 演示面板中的一个分组：标题加若干行。
export type DemoSection = {
  title: string;
  rows: DemoRow[];
};

// 演示面板中预填的查询词。
export const demoQuery = "o";
// 演示面板中显示的主动作名称。
export const demoAction = "Open Application";

// 演示面板的分组数据，顺序即渲染顺序。
export const demoSections: DemoSection[] = [
  {
    title: "Favorites",
    rows: [
      {
        title: "Ghostty",
        kind: "Application",
        icon: "ghost",
        tint: "linear-gradient(160deg, #3d5afe, #0d1b6e)",
        hotkey: ["⌥", "⌘", "T"],
      },
      {
        title: "Xcode",
        kind: "Application",
        icon: "hammer",
        tint: "linear-gradient(160deg, #5ab8ff, #1466d8)",
      },
    ],
  },
  {
    title: "Applications",
    rows: [
      {
        title: "Brave Browser",
        kind: "Application",
        icon: "shield",
        tint: "linear-gradient(160deg, #ff7a3d, #e0381c)",
      },
      {
        title: "Obsidian",
        kind: "Application",
        icon: "gem",
        tint: "linear-gradient(160deg, #a875ff, #5b12bd)",
      },
      {
        title: "Spotify",
        kind: "Application",
        icon: "audio",
        tint: "linear-gradient(160deg, #2fe06f, #14833c)",
      },
      {
        title: "OrbStack",
        kind: "Application",
        icon: "orbit",
        tint: "linear-gradient(160deg, #4c4f9e, #16173a)",
      },
    ],
  },
];
