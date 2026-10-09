// 文件职责：支持页面，展示支持 Hero、支持流程与支持者数量。
// 分层：网站 UI 层（App Router 页面）；付费内容仅为壁纸与 Discord 角色，软件仍免费开源。
import type { Metadata } from "next";
import { Footer } from "../../components/footer";
import { Nav } from "../../components/nav";
import { SupportFlow } from "../../components/support/support-flow";
import { SupporterCount } from "../../components/support/supporter-count";
import { supportHero } from "../../data/support";

// 支持页的 meta 描述：付费仅限壁纸包，软件本身保持免费开源。
const description =
  "Enjoying GearMac? Buy a premium wallpaper pack with an included Discord role. GearMac remains free and open source.";

export const metadata: Metadata = {
  title: "Enjoying GearMac?",
  description,
  alternates: { canonical: "/support/" },
  openGraph: { title: "Enjoying GearMac?", description, url: "/support/" },
};

// 支持页的标题区域，直接复用支持页的文案数据。
function Intro() {
  return (
    <header>
      <p className="font-mono text-eyebrow uppercase text-violet-bright">
        {supportHero.eyebrow}
      </p>
      <h1 className="mt-4 text-display text-fg">{supportHero.title}</h1>
      <p className="mt-5 max-w-xl text-pretty text-body-lg text-fg-muted">
        {supportHero.intro}
      </p>
      <SupporterCount />
    </header>
  );
}

// 支持页：组合导航、支持流程、标题区与页脚。
export default function SupportPage() {
  return (
    <div className="flex min-h-dvh flex-col">
      <Nav />
      <main className="mx-auto w-full max-w-7xl flex-1 px-4 pb-24 pt-12 sm:px-10 sm:pt-20">
        <SupportFlow intro={<Intro />} />
      </main>
      <Footer />
    </div>
  );
}
