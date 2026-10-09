// 文件职责：构建期访问 GitHub API 的薄封装，并派生出仓库的 API 地址。
// 分层：Service；token 可选（CI 会传入），匿名构建仍可用，但受 GitHub 每小时 60 次的限流约束。

import { site } from "../data/site";

// 从仓库链接推导出 API 地址，保持单一数据源（site.repo），不额外硬编码 slug。
const match = site.repo.match(/github\.com\/([^/]+)\/([^/]+)/);
export const repoApiUrl = match
  ? `https://api.github.com/repos/${match[1]}/${match[2]}`
  : null;

/**
 * 在构建时读取一个 GitHub API 资源。CI 会传入自己的 token，因为匿名构建会与运行器 IP 上的
 * 其他请求共享每小时 60 次的配额；本地不带 token 的构建也仍可工作。
 */
export async function readRepoJson(url: string): Promise<unknown> {
  const token = process.env.GITHUB_TOKEN;
  const res = await fetch(url, {
    headers: {
      Accept: "application/vnd.github+json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
  });
  if (!res.ok) throw new Error(`GitHub API ${res.status}`);
  return res.json();
}
