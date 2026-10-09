// 文件职责：站点根布局，配置字体、全局 metadata、结构化数据与主题 Providers。
// 分层：网站 UI 层（App Router 根布局）；字体在构建期自托管，避免第三方请求与布局偏移。
import "../index.css";

import type { Metadata } from "next";
import { Geist, Geist_Mono, Instrument_Serif } from "next/font/google";
import { Providers } from "../components/providers";
import { pageTitle, site, summary } from "../data/site";

// next/font 在构建期自托管这些字体，并为每款生成度量匹配的回退字体，
// 因此没有第三方请求，也没有布局偏移。
const geist = Geist({ subsets: ["latin"], variable: "--font-geist" });
const geistMono = Geist_Mono({
  subsets: ["latin"],
  variable: "--font-geist-mono",
});
// 唯一一款展示字体，只用于理念区的引言。加载两种字重，
// 因为引言最后一句使用斜体。
const instrumentSerif = Instrument_Serif({
  subsets: ["latin"],
  weight: "400",
  style: ["normal", "italic"],
  variable: "--font-instrument-serif",
});

// 站点级 metadata：标题模板、描述、Open Graph、Twitter 卡片、robots 与图标。
export const metadata: Metadata = {
  metadataBase: new URL(site.url),
  title: {
    default: pageTitle,
    template: "%s · GearMac",
  },
  description: summary,
  applicationName: site.name,
  alternates: { canonical: "/" },
  openGraph: {
    type: "website",
    siteName: site.name,
    url: site.url,
    locale: "en_US",
    title: pageTitle,
    description: summary,
    images: [
      {
        url: "/og.png",
        width: 1200,
        height: 630,
        alt: "The GearMac command palette open over a macOS desktop, showing fuzzy app search.",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: pageTitle,
    description: summary,
    images: ["/og.png"],
  },
  robots: { index: true, follow: true },
  icons: { icon: "/favicon.svg" },
};

// 注入首页的 Schema.org 结构化数据，声明这是一个免费的 macOS 工具应用。
const structuredData = {
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  name: site.name,
  description: summary,
  url: site.url,
  image: `${site.url}/og.png`,
  applicationCategory: "UtilitiesApplication",
  operatingSystem: site.platform,
  license: "https://www.gnu.org/licenses/agpl-3.0.html",
  offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
};

// 根布局：挂载字体 CSS 变量、主题 Providers，并向 head 注入结构化数据。
export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    // suppressHydrationWarning：next-themes 在 React 水合前就把主题 class 写到 <html> 上，
    // 这正是关键所在——它能避免主题闪烁。
    // data-scroll-behavior：Next 读取它，在路由切换期间关闭平滑滚动。
    // 否则滚动重置会带动画对抹新页面，你会落在新页面的中间位置。
    <html
      lang="en"
      className={`${geist.variable} ${geistMono.variable} ${instrumentSerif.variable}`}
      data-scroll-behavior="smooth"
      suppressHydrationWarning
    >
      <head>
        <meta name="color-scheme" content="light dark" />
        <script
          type="application/ld+json"
          // eslint-disable-next-line react/no-danger
          dangerouslySetInnerHTML={{ __html: JSON.stringify(structuredData) }}
        />
      </head>
      <body>
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
