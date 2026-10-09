// 文件职责：全站链接、安装命令与元数据的唯一数据源。
// 分层：Model（静态数据）；需要修改时只改这一处，不要在组件里到处找。

// 页面标题与 meta description，由 layout 与 /llms.txt 共用。Google 会在约 160 字符处
// 截断 description，因此 summary 的写法是控制在截断线以内而不是被切掉。
export const pageTitle = "GearMac: a free, native launcher for macOS";
export const summary =
  "A free, open source macOS launcher with app search, clipboard history, snippets, custom commands, window management, your own AI keys and Raycast extensions.";

// 站点基础元数据：名称、仓库、域名、CDN、许可与社区入口。
export const site = {
  name: "GearMac",
  repo: "https://github.com/GearMac/GearMac",
  url: "https://gearmac.dev",
  // cdn.gearmac.dev 背后的 R2 存储桶。超过 Workers 单资源 25 MiB 上限的文件
  // 放在这里而不是 `public/` —— 见 website/README.md。
  cdn: "https://cdn.gearmac.dev",
  // 仅在构建时版本查询完成前、以及查询失败时显示。
  fallbackVersion: "v0.9.7",
  platform: "macOS 26+",
  license: "AGPL-3.0",
  licenseUrl: "https://github.com/GearMac/GearMac/blob/main/LICENSE",
  community: {
    discord: "https://discord.gg/v2Eeb4QQy3",
  },
  support: "/support",
} as const;

// 首屏区块，用尽可能少的字 —— 标题加一句有力的话。
export const hero = {
  // 每行一个条目：在任何宽度下换行都落在两句之间。最后一行结尾不带标点，
  // 因为首屏会在其后绘制一个光标。
  headlineLines: ["Everything on your Mac.", "One keystroke away"],
  sub: "A small, native launcher for your apps, clipboard, snippets and windows. Free and open source, with no account and no telemetry.",
  // 按钮下方的等宽字体行。每条事实都在文档中有出处。
  facts: ["Under 100 MB of memory", "Zero dependencies", "Free & open source"],
} as const;

// 顶层导航项。
export const nav = [
  { label: "Features", href: "/#features" },
  { label: "Privacy", href: "/#privacy" },
  { label: "Docs", href: "/docs" },
  { label: "Changelog", href: "/changelog" },
] as const;

// 首屏的两行安装命令。其他所有渠道都在 docs/install.md，两个安装 CTA 都指向那里。
export const brewTrustCommand = "brew trust --tap GearMac/homebrew-gearmac";
export const brewInstallCommand =
  "brew install --cask GearMac/homebrew-gearmac/gearmac";

// 首屏下方的 Logo 墙，按渲染顺序排列。轨道从第一条开始，左边缘藏在遮罩下，
// 因此两个最不知名的名字排在前面，值得一读的品牌在加载时正好落在视口中间。
export const companies = [
  "voidzero",
  "bytedance",
  "apple",
  "google",
  "microsoft",
  "openai",
  "anthropic",
  "stripe",
  "cloudflare",
  "github",
  "samsung",
  "alibaba",
  "oracle",
  "redhat",
] as const;

// Logo 墙所支持的公司键。
export type Company = (typeof companies)[number];
