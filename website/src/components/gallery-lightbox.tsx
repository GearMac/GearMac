"use client";

// 文件职责：图库灯箱，封装 yet-another-react-lightbox 及其视频、字幕、缩略图插件。
// 分层：网站 UI 组件（客户端）；单独拆出以便首次点击图块时才加载。
import Lightbox, { type Slide } from "yet-another-react-lightbox";
import Captions from "yet-another-react-lightbox/plugins/captions";
import Thumbnails from "yet-another-react-lightbox/plugins/thumbnails";
import Video from "yet-another-react-lightbox/plugins/video";
import "yet-another-react-lightbox/styles.css";
import "yet-another-react-lightbox/plugins/captions.css";
import "yet-another-react-lightbox/plugins/thumbnails.css";

// 单独拆出，使灯箱及其三个插件在首次点击图块时才加载，
// 而不是在页面加载时——渲染网格并不需要这里的任何东西。
// 图库灯箱：接收当前索引、幻灯片与关闭回调。
export default function GalleryLightbox({
  index,
  slides,
  close,
}: {
  index: number;
  slides: Slide[];
  close: () => void;
}) {
  return (
    <Lightbox
      open={index >= 0}
      index={index}
      close={close}
      slides={slides}
      plugins={[Video, Captions, Thumbnails]}
      controller={{ closeOnBackdropClick: true }}
      noScroll={{ disabled: true }}
      // 静音自动播放是唯一跨浏览器可靠的自动播放方式；
      // （此时不被遮挡的）控件让观看者可以取消静音。
      video={{ autoPlay: true, muted: true, controls: true, playsInline: true }}
      thumbnails={{
        position: "bottom",
        width: 140,
        height: 90,
        border: 1,
        borderRadius: 10,
        gap: 12,
        padding: 4,
      }}
    />
  );
}
