// 文件职责：更新日志页面，在服务端拉取稳定版本列表并交给 Changelog 组件渲染。
// 分层：网站 UI 层（App Router 页面）；发布数据在服务端异步获取。
import type { Metadata } from "next";
import { Changelog } from "../../components/changelog";
import { Footer } from "../../components/footer";
import { Nav } from "../../components/nav";
import { ScrollTop } from "../../components/ui/scroll-top";
import { changelogCopy } from "../../data/changelog";
import { stableReleases } from "../../lib/changelog";

export const metadata: Metadata = {
  title: "Changelog",
  description: changelogCopy.description,
  alternates: { canonical: "/changelog/" },
  openGraph: {
    title: "GearMac Changelog",
    description: changelogCopy.description,
    url: "/changelog/",
  },
};

// 更新日志页：拉取稳定版本列表并渲染，页头包含导航、页脚与回顶按钮。
export default async function ChangelogPage() {
  const releases = await stableReleases();

  return (
    <>
      <Nav />
      <main className="mx-auto max-w-7xl px-4 pb-24 pt-12 sm:px-10 sm:pt-20">
        <Changelog releases={releases} />
      </main>
      <Footer />
      <ScrollTop />
    </>
  );
}
