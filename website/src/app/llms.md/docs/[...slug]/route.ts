// 文件职责：把每个文档页以原始 Markdown 返回，供 Copy Markdown 按钮与 AI agent 使用。
// 分层：网站路由层；静态导出，文件在构建期写入。
import { notFound } from "next/navigation";
import { getLLMText } from "../../../../lib/get-llm-text";
import { MARKDOWN_LEAF, source } from "../../../../lib/source";

// 每个页面以原始 Markdown 提供，供 Copy Markdown 按钮和 AI agent 使用。
// 与其他路由一样是静态的——文件在导出时写入。
export const dynamic = "force-static";
export const revalidate = false;

// 按 slug 取出页面并返回其 Markdown 文本。
export async function GET(
  _req: Request,
  { params }: { params: Promise<{ slug: string[] }> },
) {
  const { slug } = await params;
  const page = source.getPage(slug.slice(0, -1));
  if (!page) notFound();

  return new Response(await getLLMText(page), {
    headers: { "Content-Type": "text/markdown; charset=utf-8" },
  });
}

// 为每个文档页生成带 `MARKDOWN_LEAF` 后缀的静态参数。
export function generateStaticParams() {
  return source
    .generateParams()
    .map(({ slug }) => ({ slug: [...(slug ?? []), MARKDOWN_LEAF] }));
}
