// 文件职责：营销首页，按顺序组合导航、Hero、功能、图库、隐私、键盘、迁移、理念与支持等区块。
// 分层：网站 UI 层（App Router 页面）；只负责区块编排与页面宽度包裹。
import { Features } from "../components/features";
import { Footer } from "../components/footer";
import { Gallery } from "../components/gallery";
import { Ethos } from "../components/ethos";
import { Hero } from "../components/hero";
import { Keyboard } from "../components/keyboard";
import { LogoWall } from "../components/logo-wall";
import { Nav } from "../components/nav";
import { Privacy } from "../components/privacy";
import { Support } from "../components/support";
import { Switch } from "../components/switch";
import { ScrollTop } from "../components/ui/scroll-top";

// 首页：按序组合各营销区块，仅对需要统一宽度的区块包裹 max-w 容器。
export default function HomePage() {
  return (
    <>
      <Nav />
      {/* Hero 的网格与 Logo 墙都延伸到窗口边缘并自带内宽，
          因此页面宽度约束放在下面这一组容器上。 */}
      <main>
        <Hero />
        <LogoWall />
        <div className="mx-auto max-w-7xl">
          <Features />
          <Gallery />
          <Privacy />
          <Keyboard />
          <Switch />
        </div>
        <Ethos />
        <div className="mx-auto max-w-7xl">
          <Support />
        </div>
      </main>
      <Footer />
      <ScrollTop />
    </>
  );
}
