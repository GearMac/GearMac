// 文件职责：页脚，展示版权、版本号、许可证与一行导航链接。
// 分层：网站 UI 组件；单行布局，版本号在服务端获取。
import { site } from "../data/site";
import { latestVersion } from "../lib/version";
import { Logo } from "./ui/icon";
import { Link } from "./ui/link";

// 页脚导航链接列表。
const links = [
  { label: "Docs", href: "/docs" },
  { label: "Privacy", href: "/#privacy" },
  { label: "Install", href: "/docs/install" },
  { label: "Changelog", href: "/changelog" },
  { label: "GitHub", href: site.repo },
  { label: "Discord", href: site.community.discord },
  { label: "Support", href: site.support },
];

// 一条分隔线加一行链接。在这么短的页面上，三栏站点地图里的内容
// 一次滚动或一次导航点击就能到达，而它要付出的高度就是代价。
export async function Footer() {
  const version = await latestVersion();

  return (
    <footer className="border-t border-border">
      <div className="mx-auto flex max-w-7xl flex-col-reverse gap-4 px-4 py-8 sm:px-10 md:flex-row md:items-center md:justify-between">
        <div className="flex items-center gap-2.5">
          <Logo size={20} />
          <p className="text-caption text-fg-subtle">
            © {new Date().getFullYear()} {site.name} · {version} ·{" "}
            <a
              href={site.licenseUrl}
              target="_blank"
              rel="noreferrer"
              className="transition-colors hover:text-fg"
            >
              {site.license}
            </a>
          </p>
        </div>

        <nav
          aria-label="Footer"
          className="flex flex-wrap items-center gap-x-5 gap-y-2"
        >
          {links.map((link) => (
            <Link
              key={link.label}
              href={link.href}
              className="text-small text-fg-muted transition-colors hover:text-fg"
            >
              {link.label}
            </Link>
          ))}
        </nav>
      </div>
    </footer>
  );
}
