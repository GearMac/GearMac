// 文件职责：把文档页导出为纯 Markdown 文本，供“Copy Markdown”与 AI agent 使用。
// 分层：Service（fumadocs 页面适配）；输出会剔除 frontmatter，并把 description 还原为正文引用。

import type { InferPageType } from "fumadocs-core/source";
import type { source } from "./source";

// `getText("raw")` 会原样返回文件，包含 frontmatter。标题与描述会在下方以正文形式重述，
// 因此这里把那段块直接去掉，而不是两处都输出。
const FRONTMATTER = /^---\r?\n[\s\S]*?\r?\n---\r?\n?/;

/** 页面以纯 Markdown 呈现的内容 —— 即“Copy Markdown”与 AI agent 收到的文本。 */
export async function getLLMText(page: InferPageType<typeof source>) {
  const body = (await page.data.getText("raw")).replace(FRONTMATTER, "").trim();
  const description = page.data.description
    ? `\n\n> ${page.data.description}`
    : "";

  return `# ${page.data.title}${description}\n\n${body}\n`;
}
