// 文件职责：/support 页的文案与可购方案、金额配置。
// 分层：Model（静态数据）；金额以整美元为单位，Worker 再换算成 Polar 的“分”。

export type Plan = "monthly" | "one-time";

// 支持页首屏的文案。
export const supportHero = {
  eyebrow: "Support",
  title: "Enjoying GearMac?",
  intro:
    "GearMac is free and open source. If you enjoy it, consider buying a wallpaper pack and get a discord role. It would help me a lot. Thanks",
} as const;

// 结账卡片上展示的方案选项。
export const plans: { id: Plan; label: string }[] = [
  { id: "one-time", label: "One-time" },
  { id: "monthly", label: "Monthly" },
];

// 预设金额档位（美元）。
export const presetAmounts = [5, 10, 25, 50] as const;
// 允许的最大金额（美元），与 Worker 端的校验保持一致。
export const maxAmount = 10_000;

// 付款成功后的致谢文案，next 按方案区分后续步骤。
export const thanks = {
  title: "Thank you.",
  body: "Your wallpapers are ready.",
  next: {
    monthly: [
      "Polar has emailed your receipt.",
      "Your subscription renews each month until canceled. Change or cancel it anytime in your Polar customer portal.",
    ],
    "one-time": [
      "Polar has emailed your receipt.",
      "This was a one-time payment, so nothing will renew.",
    ],
  },
  perks: {
    title: "Download your wallpapers",
    body: "Sign in with your checkout email to download the pack and connect Discord to get your role.",
    action: "Open your Polar portal",
    // gearmac 组织在 Polar 的客户门户；权益在那里领取。
    href: "https://polar.sh/gearmac/portal",
  },
  share: "Know someone who lives in Spotlight? Tell them about GearMac.",
} as const satisfies {
  title: string;
  body: string;
  next: Record<Plan, readonly string[]>;
  perks: { title: string; body: string; action: string; href: string };
  share: string;
};
