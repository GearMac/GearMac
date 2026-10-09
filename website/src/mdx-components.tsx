// 文件职责：向 MDX 注入组件映射，使文档中的 <kbd> 渲染成与营销页同款按键帽组件 Kbd。
// 分层：网站 MDX 层；基础组件来自 fumadocs-ui，仅覆盖 kbd。
import defaultComponents from "fumadocs-ui/mdx";
import type { MDXComponents } from "mdx/types";
import { Kbd } from "./components/ui/kbd";

// `Kbd` 与营销页使用同款按键帽，快捷键在任何位置外观一致。
// Markdown 通过 <kbd> 抵达它。
// 返回 MDX 组件映射：在 fumadocs 默认组件之上把 kbd 换成 Kbd，并允许调用方覆盖。
export function getMDXComponents(components?: MDXComponents): MDXComponents {
  return {
    ...defaultComponents,
    kbd: Kbd,
    ...components,
  };
}
