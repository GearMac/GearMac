// 文件职责：键盘按键与快捷键组合的视觉组件 Kbd。
// 分层：UI（纯展示组件）；外观全部来自 index.css 的 .tc-key 规则。

import type { ComponentProps } from "react";
import { cn } from "../../lib/cn";

/**
 * 一个按键或快捷键组合。
 *
 * `not-prose` 是排版插件自带的退出开关。没有它，prose 主题会给 `kbd` 加上边框和
 * 固定的 13px 字号，之后每次覆写都是在跟那条规则对抗而不是替换它。
 *
 * 全部样式都在 index.css 的 `.tc-key` 规则里。
 */
export function Kbd({ className, ...props }: ComponentProps<"kbd">) {
  return <kbd className={cn("not-prose tc-key", className)} {...props} />;
}
