// 文件职责：class 名合并工具 cn，用 tailwind-merge + clsx 实现符合 Tailwind 覆写语义的类名拼接。
// 分层：Service（工具函数）；必须先教会 tailwind-merge 自定义主题，否则会误删自定义字号与阴影。

import { clsx, type ClassValue } from "clsx";
import { extendTailwindMerge } from "tailwind-merge";

// 必须把 index.css 中的自定义主题教给 tailwind-merge：否则它会把 `text-body`
// 当成文本“颜色”，在与 `text-white` 合并时错误丢弃，也不会去重自定义阴影。
const twMerge = extendTailwindMerge({
  extend: {
    classGroups: {
      "font-size": [
        {
          text: [
            "micro",
            "eyebrow",
            "caption",
            "key",
            "small",
            "body",
            "body-lg",
            "subheading",
            "stat",
            "heading",
            "demo-query",
            "demo-row",
            "demo-callout",
            "demo-section",
            "demo-key",
            "closing",
            "display",
          ],
        },
      ],
      shadow: [
        {
          shadow: [
            "key",
            "key-hover",
            "highlight",
            "keycap",
            "cap",
            "palette",
            "window",
          ],
        },
      ],
    },
  },
});

// 按 Tailwind 的覆写语义合并 class 名：后面的类覆盖前面的，
// 因此外面传进来的 `className` 能真正覆盖默认值。
export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}
