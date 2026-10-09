// 文件职责：在构建时读取最新版本号与仓库 star 数，供页头与下载入口使用。
// 分层：Service（构建期 GitHub 查询）；取不到值时回退到站点配置或返回 null，绝不编造数字。

import { site } from "../data/site";
import { readRepoJson, repoApiUrl } from "./github";

const apiUrl = repoApiUrl ? `${repoApiUrl}/releases/latest` : null;

/**
 * 最新已发布版本的 tag，在构建时读取一次并写进 HTML。放在服务端而不是浏览器里算，是
 * 为了让这个数字诚实：未认证的客户端请求受每 IP 每小时 60 次的限流，因此过去客户端版本
 * 大多数时候显示的都是过期的兜底值。
 */
export async function latestVersion(): Promise<string> {
  if (!apiUrl) return site.fallbackVersion;
  try {
    const data = await readRepoJson(apiUrl);
    const tag =
      data && typeof data === "object" && "tag_name" in data
        ? String((data as { tag_name: unknown }).tag_name)
        : "";
    return tag || site.fallbackVersion;
  } catch {
    // 构建不能因为 GitHub 不可达或被限流而失败。
    return site.fallbackVersion;
  }
}

/**
 * 仓库的 star 数，格式化为页头徽标用的字符串；与上面的版本号同理在构建时读取。
 * 无法获取时返回 null，让调用方直接隐藏徽标，而不是显示一个编造的数字。
 */
export async function starCount(): Promise<string | null> {
  if (!repoApiUrl) return null;
  try {
    const data = await readRepoJson(repoApiUrl);
    const stars =
      data && typeof data === "object" && "stargazers_count" in data
        ? Number((data as { stargazers_count: unknown }).stargazers_count)
        : NaN;
    if (!Number.isFinite(stars)) return null;
    return stars < 1000 ? String(stars) : `${(stars / 1000).toFixed(1)}k`;
  } catch {
    // 构建不能因为 GitHub 不可达或被限流而失败。
    return null;
  }
}
