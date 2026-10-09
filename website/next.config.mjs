// 文件职责：Next.js 站点配置，启用 MDX、静态导出、关闭图片优化，并开启 trailingSlash 与 React Compiler。
// 分层：网站构建配置；站点为纯静态导出，背后没有 Node 进程。
import { createMDX } from "fumadocs-mdx/next";

const withMDX = createMDX();

/** @type {import('next').NextConfig} */
const config = {
  // Cloudflare 直接托管导出后的文件——本站点背后没有 Node 进程。
  output: "export",
  // 图片优化 API 需要服务器，而静态导出没有服务器。
  images: { unoptimized: true },
  // 产出 /docs/palette/index.html，这是静态主机唯一能提供的形态。
  trailingSlash: true,
  reactCompiler: true,
};

export default withMDX(config);
