// 文件职责：顶部导航栏，展示 Logo、区块链接、支持、文档、GitHub star 数、Discord 与主题切换。
// 分层：网站 UI 组件（服务端）；滚动时玻璃化，移动端以图标替代抽屉菜单。
import { BookOpen, Star } from "lucide-react";
import { nav, site } from "../data/site";
import { starCount } from "../lib/version";
import { DiscordLogo, GitHubLogo, Logo, SupportIcon } from "./ui/icon";
import { Link } from "./ui/link";
import { ThemeSwitch } from "./ui/theme-toggle";

// 图标按钮的共用样式类。
const iconButtonClass =
  "flex size-8 items-center justify-center rounded-full text-fg-muted transition-colors hover:bg-tint/5 hover:text-fg";

// 一条细栏压在发丝线上，在 Hero 上方透明，页面滚动后变为玻璃质感。
// 手机端用图标而非菜单：区块链接一次滚动即可到达，
// 而抽屉只是多一个要打开的东西。
export async function Nav() {
  const stars = await starCount();

  return (
    <header className="header-veil sticky top-0 z-50 border-b border-border">
      <div className="mx-auto flex h-12 max-w-7xl items-center gap-6 px-4 sm:px-10">
        <Link href="/" className="flex items-center gap-2">
          <Logo size={24} />
          <span className="text-body font-semibold tracking-[-0.02em] text-fg">
            {site.name}
          </span>
        </Link>

        <nav
          aria-label="Sections"
          className="hidden items-center gap-5 md:flex"
        >
          {nav.map((item) => (
            <Link
              key={item.label}
              href={item.href}
              className="text-small text-fg-muted transition-colors hover:text-fg"
            >
              {item.label}
            </Link>
          ))}
        </nav>

        <div className="ml-auto flex items-center gap-1">
          <Link
            href={site.support}
            aria-label="Support GearMac"
            title="Support GearMac"
            className="flex h-8 items-center gap-1.5 rounded-full px-2 text-small text-fg-muted transition-colors hover:bg-tint/5 hover:text-fg sm:px-2.5"
          >
            <SupportIcon size={17} className="text-violet-bright" />
            <span className="hidden sm:inline">Support</span>
          </Link>
          <Link
            href="/docs"
            aria-label="Documentation"
            className={`${iconButtonClass} md:hidden`}
          >
            <BookOpen size={16} />
          </Link>
          <a
            href={site.repo}
            target="_blank"
            rel="noreferrer"
            aria-label={
              stars ? `${stars} stars on GitHub` : "View source on GitHub"
            }
            title="View source on GitHub"
            className={
              stars
                ? "flex h-8 items-center gap-1.5 rounded-full px-2.5 text-fg-muted transition-colors hover:bg-tint/5 hover:text-fg"
                : iconButtonClass
            }
          >
            <GitHubLogo size={16} />
            {stars && (
              <span className="inline-flex items-center gap-1 font-mono text-caption">
                <Star size={12} aria-hidden="true" />
                {stars}
              </span>
            )}
          </a>
          <a
            href={site.community.discord}
            target="_blank"
            rel="noreferrer"
            aria-label="Join the Discord"
            title="Join the Discord"
            className={iconButtonClass}
          >
            <DiscordLogo size={16} />
          </a>
          <ThemeSwitch />
        </div>
      </div>
    </header>
  );
}
