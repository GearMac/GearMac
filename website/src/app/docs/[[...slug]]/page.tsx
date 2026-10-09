// 文件职责：文档页面（可选 catch-all 路由），按 slug 取出文档并渲染 MDX、目录、复制 Markdown 与视图选项。
// 分层：网站 UI 层（App Router 动态页面）；页面不存在时调用 notFound()。
import {
  DocsBody,
  DocsDescription,
  DocsPage,
  DocsTitle,
  MarkdownCopyButton,
  ViewOptionsPopover,
} from "fumadocs-ui/layouts/docs/page";
import { notFound } from "next/navigation";
import { site } from "../../../data/site";
import { markdownUrl } from "../../../lib/markdown-url";
import { source } from "../../../lib/source";
import { getMDXComponents } from "../../../mdx-components";

// 文档页：根据路由参数查找页面，渲染正文、目录与操作按钮。
export default async function Page(props: PageProps<"/docs/[[...slug]]">) {
  const params = await props.params;
  const page = source.getPage(params.slug);
  if (!page) notFound();

  const MDX = page.data.body;
  const markdown = markdownUrl(page.url);

  return (
    <DocsPage toc={page.data.toc} full={page.data.full}>
      <DocsTitle>{page.data.title}</DocsTitle>
      {/* 默认的 `mb-8` 会让操作按钮漂浮在描述下方的远处；
          它们应属于标题块，而不是游离在外。 */}
      <DocsDescription className="mb-4">
        {page.data.description}
      </DocsDescription>
      <div className="flex flex-row items-center gap-2 border-b pb-4">
        <MarkdownCopyButton markdownUrl={markdown} />
        <ViewOptionsPopover
          markdownUrl={markdown}
          githubUrl={`${site.repo}/blob/main/website/content/docs/${page.path}`}
        />
      </div>
      <DocsBody>
        <MDX components={getMDXComponents()} />
      </DocsBody>
    </DocsPage>
  );
}

// 供静态导出预生成全部文档页参数。
export function generateStaticParams() {
  return source.generateParams();
}

// 生成文档页的 metadata（标题、描述、canonical 与 Open Graph）。
export async function generateMetadata(props: PageProps<"/docs/[[...slug]]">) {
  const params = await props.params;
  const page = source.getPage(params.slug);
  if (!page) notFound();

  // `trailingSlash` 才是主机实际提供的路径，因此 canonical 也必须带上斜杠。
  const canonical = `${page.url}/`;

  return {
    title: page.data.title,
    description: page.data.description,
    alternates: { canonical },
    openGraph: {
      url: canonical,
      title: page.data.title,
      description: page.data.description,
    },
  };
}
