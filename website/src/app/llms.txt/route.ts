// 文件职责：生成 llms.txt 索引，按章节汇总所有文档页及其原始 Markdown 链接。
// 分层：网站路由层；输出纯文本，静态导出。
import { site, summary } from "../../data/site";
import { markdownUrl } from "../../lib/markdown-url";
import { source } from "../../lib/source";

// 遵循 llms.txt 约定：一份 Markdown 索引，agent 一次拉取即可读完，
// 每页的原始 Markdown 只差一个链接。按章节分组，因为平铺的 37 条只会噪声一片。
export const dynamic = "force-static";
export const revalidate = false;

// 章节键（URL 片段）到 llms.txt 标题的映射。
const SECTIONS: Record<string, string> = {
  "": "Start here",
  launcher: "Launcher",
  features: "Features",
  ai: "AI",
  extensions: "Raycast extensions",
  reference: "Reference",
};

// 生成 llms.txt 响应体的路由处理函数。
export function GET() {
  const grouped = new Map<string, string[]>();

  for (const page of source.getPages()) {
    const segments = page.url.replace("/docs", "").split("/").filter(Boolean);
    // 匹配任意片段，使章节自身的落地页归入该章节，而不是排在它之上。
    const section = segments.find((segment) => segment in SECTIONS) ?? "";
    const description = page.data.description
      ? `: ${page.data.description}`
      : "";
    const line = `- [${page.data.title}](${site.url}${markdownUrl(page.url)})${description}`;
    grouped.set(section, [...(grouped.get(section) ?? []), line]);
  }

  const body = Object.entries(SECTIONS)
    .filter(([key]) => grouped.has(key))
    .map(
      ([key, heading]) =>
        `## ${heading}\n\n${grouped.get(key)!.sort().join("\n")}`,
    )
    .join("\n\n");

  return new Response(`# ${site.name}\n\n> ${summary}\n\n${body}\n`, {
    headers: { "Content-Type": "text/plain; charset=utf-8" },
  });
}
