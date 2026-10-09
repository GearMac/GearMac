"use client";

// 文件职责：右下角的“回到顶部”浮动按钮，滚过首屏后淡入上浮，接近顶部时淡出。
// 分层：UI（"use client" 客户端组件）；样式与导航栏一致（磨砂面、细边框、键帽抬升），并尊重 prefers-reduced-motion。

import { ArrowUp } from "lucide-react";
import { useEffect, useState } from "react";
import { cn } from "../../lib/cn";

// 滚动超过首屏后淡入上浮的“回到顶部”控件，接近顶部时缓缓退场。样式与导航栏一致
// （画布上的磨砂面、细边框、键帽抬升），看起来属于同一套视觉体系。动效遵循 prefers-reduced-motion。
export function ScrollTop() {
  const [shown, setShown] = useState(false);

  useEffect(() => {
    const onScroll = () => setShown(window.scrollY > 600);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  function toTop() {
    const reduce = window.matchMedia(
      "(prefers-reduced-motion: reduce)",
    ).matches;
    window.scrollTo({ top: 0, behavior: reduce ? "auto" : "smooth" });
  }

  return (
    <button
      type="button"
      onClick={toTop}
      aria-label="Back to top"
      aria-hidden={!shown}
      tabIndex={shown ? 0 : -1}
      className={cn(
        "group fixed bottom-6 right-6 z-40 flex size-11 items-center justify-center rounded-full border border-border bg-canvas/60 text-fg-muted shadow-key backdrop-blur-2xl transition-all duration-300 ease-out hover:border-border-strong hover:text-fg hover:shadow-key-hover",
        shown
          ? "translate-y-0 scale-100 opacity-100"
          : "pointer-events-none translate-y-4 scale-90 opacity-0",
      )}
    >
      <ArrowUp
        size={19}
        strokeWidth={2}
        className="transition-transform duration-200 group-hover:-translate-y-0.5"
      />
    </button>
  );
}
