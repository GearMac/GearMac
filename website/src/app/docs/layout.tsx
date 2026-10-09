// 文件职责：文档区布局，用 DocsProvider 与 fumadocs DocsLayout 组织侧边栏、导航与底部链接。
// 分层：网站 UI 层（App Router 布局）；侧边栏使用全宽以消除多余边距。
import { DocsLayout } from "fumadocs-ui/layouts/docs";
import type { ReactNode } from "react";
import { DocsProvider } from "../../components/docs-provider";
import {
  DiscordLogo,
  GitHubLogo,
  Logo,
  SupportIcon,
} from "../../components/ui/icon";
import { site } from "../../data/site";
import { source } from "../../lib/source";

// 文档区布局：向 DocsLayout 提供页面树与侧边栏底部链接。
export default function Layout({ children }: { children: ReactNode }) {
  return (
    <DocsProvider>
      <DocsLayout
        tree={source.pageTree}
        // 网格会在 `--fd-layout-width` 内居中，在宽屏上会在侧边栏左侧留下
        // 空白边距。设为全宽可折叠该边距，让侧边栏紧贴边缘。
        containerProps={{ style: { "--fd-layout-width": "100%" } as never }}
        // `type: "icon"` 才能把它们放在侧边栏底栏、主题切换旁边。
        // 若改用 `githubUrl`，GitHub 会出现在那里，但 Discord 无处安放。
        links={[
          // 按钮而非图标：16pt 的字形会被 GitHub 和 Discord 淹没。
          {
            type: "button",
            text: (
              <span className="flex items-center gap-1.5">
                <SupportIcon size={15} />
                Support
              </span>
            ),
            url: site.support,
          },
          {
            type: "icon",
            text: "GitHub",
            label: "GitHub repository",
            url: site.repo,
            icon: <GitHubLogo size={16} />,
            external: true,
          },
          {
            type: "icon",
            text: "Discord",
            label: "Join the Discord",
            url: site.community.discord,
            icon: <DiscordLogo size={16} />,
            external: true,
          },
        ]}
        nav={{
          title: (
            <span className="flex items-center gap-1.5 font-semibold text-fg">
              <Logo size={22} />
              {site.name}
            </span>
          ),
        }}
      >
        {children}
      </DocsLayout>
    </DocsProvider>
  );
}
