// 文件职责：把文档页面的 URL 映射到它原始 Markdown 副本的地址。
// 分层：Service（URL 工具）；命名必须与 app/llms.md/docs 路由保持一致。

import { MARKDOWN_LEAF } from "./source";

/** 页面原始 Markdown 的位置 —— 路由见 `app/llms.md/docs`。 */
export function markdownUrl(pageUrl: string): string {
  const slug = pageUrl.replace(/^\/docs\/?/, "");
  return `/llms.md/docs/${slug ? `${slug}/` : ""}${MARKDOWN_LEAF}`;
}
