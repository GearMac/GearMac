// 文件职责：收尾区块的文案，包含核心宣言 ethos 与四条价值主张 ethosPillars。
// 分层：Model（静态数据）；这里的每条主张都必须在文档中有出处（Getting started、
// Permissions、Extensions、AI），不要新增无出处的说法。

// 单条价值主张：图标键、标题与正文。
export type EthosPillar = {
  icon: "native" | "local" | "source" | "free";
  title: string;
  body: string;
};

// 收尾区的宣言：引用句、强调句与署名。
export const ethos = {
  quote: "No account. No telemetry.",
  // 以斜体呈现，让它读起来像点睛之笔，而不是第三个并列从句。
  emphasis: "No bullshit.",
  attribution: "the whole privacy policy, more or less",
} as const;

// 四条价值主张，顺序即页面上的呈现顺序。
export const ethosPillars: EthosPillar[] = [
  {
    icon: "native",
    title: "Native",
    body: "Written in Swift 6 with SwiftUI and AppKit, and no third-party dependencies. It opens fast and stays under 100 MB of memory.",
  },
  {
    icon: "local",
    title: "Local",
    body: "Your clipboard, notes and snippets are stored on your Mac. AI stays off until you turn it on and pick a provider.",
  },
  {
    icon: "source",
    title: "Open source",
    body: "The full source is on GitHub under AGPL-3.0, and you can build it yourself. The scope stays narrow so the app stays small.",
  },
  {
    icon: "free",
    title: "Free",
    body: "Every feature is free, and there is no Pro tier. Optional tips pay the running costs.",
  },
];
