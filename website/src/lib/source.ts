// 文件职责：构建 fumadocs 文档源（source loader），并导出逐页 Markdown 的叶子文件名常量。
// 分层：Service（fumadocs 配置）；仅服务 /docs 文档树，页面路径与文件名的映射规则在此固定。

import { loader } from "fumadocs-core/source";
import { docs } from "../../.source/server";

// `/docs` 是唯一的文档树；它之上的所有路由由营销页负责。
export const source = loader({
  baseUrl: "/docs",
  source: docs.toFumadocsSource(),
});

/**
 * 每个页面的原始 Markdown 都输出为 `<页面路径>/index.md`。
 *
 * 静态导出会为每条路由写一个文件，因此当一个页面同时也是目录时 —— 例如
 * `/docs/launcher` 还有子页面 —— 它不能在同一路径上既是文件又是目录。
 * 给每个页面一个叶子文件，可以从根源上消除这类冲突，而不是对那些恰好有子页面的
 * 页面做特例处理。
 */
export const MARKDOWN_LEAF = "index.md";
