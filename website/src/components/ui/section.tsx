// 文件职责：营销页的区块骨架组件，提供 SectionLabel 序号标签与带标题的 Section 容器。
// 分层：UI（服务端可用的展示组件）；index 决定区块在页面上的序号，按自上而下的阅读顺序编号。

import type { ReactNode } from "react";

type SectionProps = {
  id: string;
  /** 区块在页面上的位置，显示为 "01"。区块按自上而下的顺序阅读。 */
  index: number;
  label: string;
  title: ReactNode;
  intro?: ReactNode;
  children: ReactNode;
};

// 区块的序号 + 标签行，用于在标题上方标注当前小节。
export function SectionLabel({
  index,
  label,
}: {
  index: number;
  label: string;
}) {
  return (
    <p className="flex items-baseline gap-2.5 font-mono text-eyebrow uppercase">
      <span className="text-violet-bright">
        {String(index).padStart(2, "0")}
      </span>
      <span className="text-fg-muted">{label}</span>
    </p>
  );
}

// 营销页的标准区块：锚点 id、上方的小节标签、标题、可选导语与正文内容。
export function Section({
  id,
  index,
  label,
  title,
  intro,
  children,
}: SectionProps) {
  const header = (
    <div className="max-w-2xl">
      <SectionLabel index={index} label={label} />
      <h2 className="mt-4 text-heading">{title}</h2>
      {intro && (
        <p className="mt-4 max-w-xl text-pretty text-body-lg text-fg-muted">
          {intro}
        </p>
      )}
    </div>
  );

  return (
    <section id={id} className="relative">
      <div className="px-4 py-20 sm:px-10 sm:py-24">
        {header}
        <div className="mt-12">{children}</div>
      </div>
    </section>
  );
}
