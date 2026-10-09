// 文件职责：“GearMac 实拍”画廊与灯箱的数据源，每个条目既是网格中的一块，也是灯箱里的一页。
// 分层：Model（静态数据）；src/thumb/poster 是渲染时的 URL（public/ 用根绝对路径，R2 用绝对 URL），
// width/height 是媒体的真实像素尺寸（用于灯箱比例），网格图块固定 16:9。

import { site } from "./site";

// 画廊中的一个条目：图片或视频。
export type GalleryItem = {
  type: "image" | "video";
  // 灯箱中展示的原尺寸媒体（图片 src，视频则为视频文件）。
  src: string;
  // 网格缩略图；缺省时回退到 `poster`（视频）或 `src`（图片）。
  thumb?: string;
  // 视频图块/幻灯的首帧封面。
  poster?: string;
  title: string;
  caption: string;
  width: number;
  height: number;
};

// 画廊条目，顺序即网格与灯箱中的呈现顺序。
export const galleryItems: GalleryItem[] = [
  {
    type: "video",
    src: `${site.cdn}/gearmac-in-action.mp4`,
    poster: "/screenshot.png",
    title: "GearMac in action",
    caption:
      "A short tour of the launcher, clipboard history, calculator and more.",
    width: 3024,
    height: 1964,
  },
  {
    type: "image",
    src: "/calculator.png",
    title: "Inline calculator",
    caption: "Answers math and converts units and currencies as you type.",
    width: 2148,
    height: 1302,
  },
  {
    type: "image",
    src: "/clipboard.png",
    title: "Clipboard history",
    caption:
      "Search the text and images you've copied. History is stored only on your Mac.",
    width: 2092,
    height: 1268,
  },
  {
    type: "image",
    src: "/unlimited-clipboard-history.png",
    title: "Keep history as long as you want",
    caption: "Choose how long history is kept, from one day to forever.",
    width: 2226,
    height: 1604,
  },
  {
    type: "image",
    src: "/emoji.png",
    title: "Emoji & symbols",
    caption: "Search every emoji. The ones you use most show up first.",
    width: 2106,
    height: 1244,
  },
  {
    type: "image",
    src: "/per-app-hotkey.png",
    title: "Per-app hotkeys",
    caption:
      "Give an app its own shortcut. Press it to bring the app forward, and again to hide it.",
    width: 2212,
    height: 1606,
  },
  {
    type: "image",
    src: "/ram-usage.png",
    title: "Light on memory",
    caption: "Stays under 100 MB of memory, no matter how long it runs.",
    width: 2558,
    height: 1754,
  },
  {
    type: "image",
    src: "/backup-import-settings.png",
    title: "Backup & import",
    caption: "Export your setup to one file and restore it on any Mac.",
    width: 2098,
    height: 1600,
  },
];
