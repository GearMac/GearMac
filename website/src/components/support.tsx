// 文件职责：首页支持区块，展示品牌光晕、支持文案与「获取壁纸 / GitHub Star」按钮。
// 分层：网站 UI 组件；纯展示链接，不含支付逻辑。
import { site } from "../data/site";
import { supportHero } from "../data/support";
import { Button } from "./ui/button";
import { GitHubLogo, Logo, SupportIcon } from "./ui/icon";

// 品牌标记单独置于紫色光晕上，使页面以品牌收尾。
function GlowingMark() {
  return (
    <span className="relative mx-auto flex size-28 items-center justify-center sm:size-32">
      <span
        aria-hidden="true"
        className="mark-bloom pointer-events-none absolute -inset-32"
      />
      <Logo size={72} className="relative" />
    </span>
  );
}

// 首页支持区块：品牌光晕、文案与两个行动按钮。
export function Support() {
  return (
    <section id="support" className="px-4 pb-24 pt-24 text-center sm:px-10 ">
      <div aria-hidden="true">
        <GlowingMark />
      </div>
      <h2 className="mx-auto mt-14 max-w-2xl text-closing">
        {supportHero.title}
      </h2>
      <p className="mx-auto mt-4 max-w-lg text-pretty text-body-lg text-fg-muted">
        {supportHero.intro}
      </p>
      <div className="mt-8 flex flex-wrap justify-center gap-3">
        <Button href={site.support} size="lg">
          <SupportIcon size={18} />
          Get wallpapers
        </Button>
        <Button href={site.repo} variant="ghost" size="lg">
          <GitHubLogo size={16} />
          Star on GitHub
        </Button>
      </div>
    </section>
  );
}
