// 文件职责：生成站点地图，列出首页、支持页、更新日志页及全部文档页。
// 分层：网站路由层；导出必须为 force-static，静态导出没有请求可响应。
import type { MetadataRoute } from "next";
import { site } from "../data/site";
import { source } from "../lib/source";

// 从文档树生成，新页面一出现即被收录。
// `dynamic` 必须保持 "force-static"：静态导出没有请求可响应。
export const dynamic = "force-static";

// 生成站点地图条目：静态页面 + 全部文档页。
export default function sitemap(): MetadataRoute.Sitemap {
  const now = new Date();

  return [
    { url: `${site.url}/`, lastModified: now, priority: 1 },
    { url: `${site.url}/support/`, lastModified: now, priority: 0.8 },
    { url: `${site.url}/changelog/`, lastModified: now, priority: 0.6 },
    ...source.getPages().map((page) => ({
      url: `${site.url}${page.url}/`,
      lastModified: now,
      priority: 0.7,
    })),
  ];
}
