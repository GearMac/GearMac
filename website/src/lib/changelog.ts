// 文件职责：在构建时读取 GitHub Releases 并解析为结构化的稳定版本列表，供 /changelog 页面渲染。
// 分层：Service（构建期数据获取与解析）；网络失败时返回 null 而不是抛错，构建不能因 GitHub 不可用而失败。

import { readRepoJson, repoApiUrl } from "./github";

// Scripts/release-notes.sh 会在这行下方放安装文本；上方的部分才是发布说明。
const INSTALL_MARKER = "<!-- gearmac:install -->";
// 更新器自身的规则：其他任何情况（beta、一次性构建）都不是稳定版。
const STABLE_TAG = /^v(\d+)\.(\d+)\.(\d+)$/;
// GitHub 分页大小与最多翻页数。
const PAGE_SIZE = 100;
const MAX_PAGES = 10;

// GitHub 自动生成的发布说明格式，兼容发布脚本缩短 PR 链接前后的两种形态。
const CHANGE_LINE =
  /^\* (.+) by @([\w-]+(?:\[bot\])?) in (?:#|https:\/\/github\.com\/[^/]+\/[^/]+\/pull\/)(\d+)$/;
const COMPARE_LINK = /\[Full changelog\]\((\S+)\)/;
// 有少量 PR 用了 Conventional Commit 风格的标题；这个前缀在更新日志里是噪音。
const COMMIT_PREFIX =
  /^(?:feat|fix|chore|docs|refactor|perf|style|test|build|ci)(?:\([^)]*\))?!?:\s*/i;

// 单条变更：标题、作者（可能缺失）与 PR 编号（可能缺失）。
export type Change = {
  title: string;
  author: string | null;
  pr: number | null;
};

// 贡献者及其变更数量。
export type Contributor = {
  login: string;
  changes: number;
};

// 一个稳定版本的完整信息。
export type StableRelease = {
  version: string;
  tag: string;
  publishedAt: string;
  url: string;
  compareUrl: string | null;
  /** 对于在“由合并 PR 生成说明”之前发布的版本为 false。 */
  hasNotes: boolean;
  /** 发布说明中的散文部分，例如没有合并 PR 的版本所携带的那行文字。 */
  summary: string | null;
  changes: Change[];
  contributors: Contributor[];
};

// GitHub Releases API 响应中我们实际使用的字段。
type ApiRelease = {
  tag_name: string;
  draft: boolean;
  prerelease: boolean;
  published_at: string | null;
  html_url: string;
  body: string | null;
};

// 校验任意值是否为可用的 GitHub Release 响应。
function isApiRelease(value: unknown): value is ApiRelease {
  if (!value || typeof value !== "object") return false;
  const release = value as Record<string, unknown>;
  return (
    typeof release.tag_name === "string" &&
    typeof release.html_url === "string" &&
    typeof release.draft === "boolean" &&
    typeof release.prerelease === "boolean"
  );
}

// 去掉 Conventional Commit 前缀并把首字母大写。
function cleanTitle(title: string): string {
  const bare = title.replace(COMMIT_PREFIX, "").trim();
  return bare.charAt(0).toUpperCase() + bare.slice(1);
}

// 把 GitHub 的 Markdown 发布说明解析为变更列表与散文摘要。
function parseNotes(notes: string) {
  const changes: Change[] = [];
  const prose: string[] = [];
  let section = "";

  for (const raw of notes.split(/\r?\n/)) {
    const line = raw.trim();
    if (line.startsWith("## ")) {
      section = line.slice(3).toLowerCase();
      continue;
    }
    if (!line.startsWith("* ")) {
      if (line) prose.push(line);
      continue;
    }

    // 这里列出的人已在其变更中被署名，无需重复统计。
    if (section.startsWith("new contributors")) continue;
    const match = line.match(CHANGE_LINE);
    changes.push(
      match
        ? {
            title: cleanTitle(match[1]),
            author: match[2],
            pr: Number(match[3]),
          }
        : { title: cleanTitle(line.slice(2)), author: null, pr: null },
    );
  }

  return { changes, summary: prose.join(" ") || null };
}

// 按变更数降序排列；数量相同时保持它们在说明中出现的先后顺序。
function rankContributors(changes: Change[]): Contributor[] {
  const counts = new Map<string, number>();
  for (const { author } of changes) {
    if (author) counts.set(author, (counts.get(author) ?? 0) + 1);
  }
  return [...counts]
    .map(([login, count]) => ({ login, changes: count }))
    .sort((a, b) => b.changes - a.changes);
}

// 把 API 响应转换为 StableRelease；草稿、预发布或非稳定 tag 返回 null。
function toStableRelease(release: ApiRelease): StableRelease | null {
  if (release.draft || release.prerelease) return null;
  if (!STABLE_TAG.test(release.tag_name) || !release.published_at) return null;

  const body = release.body ?? "";
  const [notes, install] = body.split(INSTALL_MARKER);
  const hasNotes = install !== undefined;
  const { changes, summary } = parseNotes(hasNotes ? notes : "");
  return {
    version: release.tag_name.slice(1),
    tag: release.tag_name,
    publishedAt: release.published_at,
    url: release.html_url,
    compareUrl: body.match(COMPARE_LINK)?.[1] ?? null,
    hasNotes,
    summary,
    changes,
    contributors: rankContributors(changes),
  };
}

// 从 tag 中取出主/次/修订号。
function versionParts(tag: string): number[] {
  return (tag.match(STABLE_TAG) ?? []).slice(1).map(Number);
}

// 按语义版本号从新到旧排序。
function byVersionDescending(a: StableRelease, b: StableRelease): number {
  const left = versionParts(a.tag);
  const right = versionParts(b.tag);
  for (let i = 0; i < 3; i++) {
    if (left[i] !== right[i]) return right[i] - left[i];
  }
  return 0;
}

/**
 * 所有稳定版本，最新的在前，在构建时只读取一次。GitHub 无法访问时返回 null，
 * 让页面如实说明而不是声称没有任何版本。
 */
export async function stableReleases(): Promise<StableRelease[] | null> {
  if (!repoApiUrl) return null;
  try {
    const releases: StableRelease[] = [];
    for (let page = 1; page <= MAX_PAGES; page++) {
      const batch = await readRepoJson(
        `${repoApiUrl}/releases?per_page=${PAGE_SIZE}&page=${page}`,
      );
      if (!Array.isArray(batch)) throw new Error("Unexpected releases payload");
      for (const item of batch) {
        const release = isApiRelease(item) ? toStableRelease(item) : null;
        if (release) releases.push(release);
      }
      if (batch.length < PAGE_SIZE) break;
    }
    return releases.sort(byVersionDescending);
  } catch {
    // 构建不能因为 GitHub 不可达或被限流而失败。
    return null;
  }
}
