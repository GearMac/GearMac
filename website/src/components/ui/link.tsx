// 文件职责：站内链接统一入口，内部路径交给 next/link，外部与锚点降级为原生 a。
// 分层：UI（纯展示组件）；外链自动补 target 与 rel 防护。

import NextLink from "next/link";
import type { ComponentProps } from "react";

// href 为必填，因此从 NextLink 的 props 中排除，再重新声明为非可选。
type Props = Omit<ComponentProps<typeof NextLink>, "href"> & { href: string };

/**
 * 站内链接，包括页内锚点。外部 URL 会降级为原生 anchor，并带上惯常的 rel 防护。
 */
export function Link({ href, ...props }: Props) {
  if (/^(https?:|mailto:|#)/.test(href)) {
    const external = href.startsWith("http");
    return (
      <a
        href={href}
        {...(external ? { target: "_blank", rel: "noreferrer" } : {})}
        {...props}
      />
    );
  }

  return <NextLink href={href} {...props} />;
}
