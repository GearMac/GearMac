"use client";

// 文件职责：图库区块，渲染缩略图网格并在点击时打开灯箱，自行管理滚动锁定。
// 分层：网站 UI 组件（客户端）；灯箱按需动态加载，首屏不引入其体积。
import { Play } from "lucide-react";
import dynamic from "next/dynamic";
import Image from "next/image";
import { useEffect, useState } from "react";
import type { Slide } from "yet-another-react-lightbox";
import { galleryItems, type GalleryItem } from "../data/gallery";
import { cn } from "../lib/cn";
import { Section } from "./ui/section";

// 灯箱体积约 30 KB（gzip），在点击图块之前不做任何事。
const GalleryLightbox = dynamic(() => import("./gallery-lightbox"));

// 网格缩略图：优先显式 thumb，否则取视频的 poster，再否则取图片本身。
const tileImage = (item: GalleryItem) =>
  item.thumb ?? (item.type === "video" ? (item.poster ?? item.src) : item.src);

// 一个图库条目 → 一张灯箱幻灯片。图片携带 title/description 供字幕插件使用；
// 视频使用 Video 插件的 `sources` 结构。
function toSlide(item: GalleryItem): Slide {
  if (item.type === "video") {
    return {
      type: "video",
      poster: item.poster,
      width: item.width,
      height: item.height,
      title: item.title,
      description: item.caption,
      sources: [{ src: item.src, type: "video/mp4" }],
    };
  }
  return {
    src: item.src,
    title: item.title,
    description: item.caption,
    width: item.width,
    height: item.height,
  };
}

// 图库区块：渲染缩略图网格，并在首次打开后常驻挂载灯箱。
export function Gallery() {
  const [index, setIndex] = useState(-1);
  // 一旦打开过就保持挂载，使关闭再重开无需重新拉取。
  const [everOpened, setEverOpened] = useState(false);

  function open(i: number) {
    setEverOpened(true);
    setIndex(i);
  }

  // 自行锁定滚动，而不用灯箱自带的模块：它会把滚动条宽度补到 <body> 上，
  // 并影响每个固定定位元素（包括回顶按钮，使其箭头偏移）。
  // `scrollbar-gutter: stable` 已预留了那块空间，所以单纯的 overflow:hidden
  // 锁定不会改变任何宽度——也就没有位移。
  useEffect(() => {
    if (index < 0) return;
    const html = document.documentElement;
    const previous = html.style.overflow;
    html.style.overflow = "hidden";
    return () => {
      html.style.overflow = previous;
    };
  }, [index]);

  return (
    <Section
      id="gallery"
      index={2}
      label="In action"
      title="Straight from the app."
      intro="The palette at the top of this page is a recreation. These screenshots come from GearMac itself. Click one to see it full size."
    >
      <div className="overflow-hidden rounded-xl border border-border/70 bg-surface shadow-xs">
        <div className="flex min-h-11 items-center gap-3 border-b border-border/60 px-4 py-1.5 font-mono text-micro uppercase text-fg-muted">
          <span
            aria-hidden="true"
            className="size-1.5 rounded-full bg-violet"
          />
          Captured in GearMac
          <span className="ml-auto hidden sm:inline">Click any to enlarge</span>
        </div>
        {/* 导览视频以双倍尺寸置顶，最后一张静态图也占双倍宽度，
            使静态图无间隙地填满每一行。 */}
        <div className="grid gap-3 p-3 sm:grid-cols-2 lg:grid-cols-4">
          {galleryItems.map((item, i) => {
            const isLead = i === 0;
            const isLast = i === galleryItems.length - 1;
            return (
              <button
                key={`${item.title}-${i}`}
                type="button"
                onClick={() => open(i)}
                className={cn(
                  "group flex flex-col gap-2 text-left",
                  isLead && "sm:col-span-2 lg:row-span-2",
                  isLast && "sm:col-span-2",
                )}
              >
                <figure
                  className={cn(
                    "relative aspect-video w-full overflow-hidden rounded-lg ring-1 ring-border/60 transition-shadow duration-200 group-hover:ring-border-strong",
                    (isLead || isLast) && "lg:aspect-auto lg:flex-1",
                  )}
                >
                  <Image
                    src={tileImage(item)}
                    alt={item.title}
                    fill
                    sizes={
                      isLead || isLast
                        ? "(min-width: 640px) 50vw, 90vw"
                        : "(min-width: 1024px) 25vw, (min-width: 640px) 45vw, 90vw"
                    }
                    className="object-cover transition-transform duration-300 group-hover:scale-[1.02]"
                  />
                  {item.type === "video" && (
                    <span className="absolute inset-0 flex items-center justify-center">
                      <span className="flex size-16 items-center justify-center rounded-full bg-fg text-canvas transition-transform duration-200 group-hover:scale-105">
                        <Play size={24} fill="currentColor" />
                      </span>
                    </span>
                  )}
                </figure>
                <div>
                  <h3 className="text-small font-medium text-fg">
                    {item.title}
                  </h3>
                  <p className="text-small text-fg-muted">{item.caption}</p>
                </div>
              </button>
            );
          })}
        </div>
      </div>

      {everOpened && (
        <GalleryLightbox
          index={index}
          slides={galleryItems.map(toSlide)}
          close={() => setIndex(-1)}
        />
      )}
    </Section>
  );
}
