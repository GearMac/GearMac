// 文件职责：渲染为按钮外观的链接组件，统一全站 CTA 的变体与尺寸。
// 分层：UI（服务端可用的展示组件）；本身不发请求、不带交互状态，一律渲染为 Link。

import type { ComponentProps, ReactNode } from "react";
import { cn } from "../../lib/cn";
import { Link } from "./link";

// 视觉变体：primary 品牌紫、action 高对比主操作面、ghost 无底、outline 描边。
type Variant = "primary" | "action" | "ghost" | "outline";
// 尺寸档位，决定高度、间距与字号。
type Size = "sm" | "md" | "lg";

type ButtonProps = {
  children: ReactNode;
  href: string;
  variant?: Variant;
  size?: Size;
} & Omit<ComponentProps<typeof Link>, "href">;

// 每个变体自带圆角：胶囊形读起来像网页 CTA，放在应用内的操作面上不合适，
// 而那个操作面偏方形，和 app 自身一致。
const variants: Record<Variant, string> = {
  // 品牌紫只标记唯一重要的动作：获取应用。
  primary: "rounded-full bg-violet text-white hover:bg-violet-deep",
  // 浅色主题下墨黑配白、深色主题下纸白配黑 —— 两种主题里对比度最高的表面。
  action: "rounded-md bg-action text-action-fg hover:opacity-90",
  ghost: "rounded-full text-fg-muted hover:bg-tint/5 hover:text-fg",
  outline:
    "rounded-full border border-border text-fg-muted hover:border-border-strong hover:text-fg",
};

const sizes: Record<Size, string> = {
  sm: "h-7 gap-1 px-3.5 text-small",
  md: "h-9 gap-2 px-3.5 text-small",
  lg: "h-11 gap-2 px-6 text-body",
};

// 外观像按钮的链接。本页所有入口（下载 / 锚点 / 仓库）都是链接，因此用 anchor 最诚实。
export function Button({
  children,
  href,
  variant = "primary",
  size = "sm",
  className,
  ...props
}: ButtonProps) {
  return (
    <Link
      href={href}
      className={cn(
        "inline-flex shrink-0 items-center justify-center whitespace-nowrap font-medium transition-colors active:translate-y-px",
        variants[variant],
        sizes[size],
        className,
      )}
      {...props}
    >
      {children}
    </Link>
  );
}
