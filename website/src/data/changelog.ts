// 文件职责：/changelog 页面的界面文案常量。
// 分层：Model（静态数据）；版本数据本身在构建时从 GitHub 读取，不在这里硬编码。

export const changelogHero = {
  eyebrow: "Changelog",
  title: "What's new",
  intro: "What changed in each release of GearMac, and who contributed.",
} as const;

// 变更日志页的其余界面文案；showMore/contributors 是按数量拼词的函数。
export const changelogCopy = {
  description: "What changed in each GearMac release, and who contributed.",
  jumpTo: "Versions",
  latest: "Latest",
  releaseNotes: "View on GitHub",
  compare: "View diff",
  showMore: (count: number) => `Show ${count} more`,
  contributors: (count: number) =>
    `Thanks to ${count} ${count === 1 ? "contributor" : "contributors"}`,
  earlier: {
    title: "Earlier releases",
    body: "These releases came before release notes. Each one links to its download.",
  },
  unavailable: {
    title: "Changelog unavailable",
    body: "GitHub didn't respond when this page was built. You can still find every release on GitHub.",
  },
  allReleases: "All releases on GitHub",
  install: "Get GearMac",
} as const;
