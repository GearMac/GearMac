"use client";

// 文件职责：支持页的左栏介绍与右侧结账卡片的编排容器，并根据 Polar 回跳参数切换到致谢视图。
// 分层：UI（"use client" 客户端组件）；仅在 hydration 后读取一次 URL 状态。

import { useEffect, useState, type ReactNode } from "react";
import type { Plan } from "../../data/support";
import { CheckoutCard } from "./checkout-card";
import { ThankYou } from "./thank-you";

// Polar 付款成功回跳时携带的方案参数名。
const THANKS_PARAM = "thanks";

// 把 URL 参数解析为已知方案；无法识别时返回 null。
function parsePlan(value: string | null): Plan | null {
  return value === "monthly" || value === "one-time" ? value : null;
}

type Props = {
  // 页面传入的介绍内容，渲染在卡片左侧。
  intro: ReactNode;
};

// 支持页的主流程：左侧展示介绍，右侧展示结账卡片或付款后的致谢。
export function SupportFlow({ intro }: Props) {
  const [returned, setReturned] = useState<Plan | null>(null);

  // Polar 回跳会带上 ?thanks=<plan>；这里把它删掉，这样再刷新时会重新显示结账卡片。
  useEffect(() => {
    const url = new URL(window.location.href);
    const plan = parsePlan(url.searchParams.get(THANKS_PARAM));
    if (!plan) return;
    url.searchParams.delete(THANKS_PARAM);
    window.history.replaceState(window.history.state, "", url);
    // oxlint-disable-next-line react/set-state-in-effect -- URL 只能在 hydration 之后读取
    setReturned(plan);
  }, []);

  return (
    <div className="grid items-start gap-10 lg:grid-cols-[minmax(0,1fr)_420px] lg:gap-20">
      {intro}
      <div className="relative">
        <span
          aria-hidden="true"
          className="mark-bloom pointer-events-none absolute inset-x-0 -top-16 h-72 opacity-60"
        />
        <div className="relative lg:sticky lg:top-20">
          {returned ? <ThankYou plan={returned} /> : <CheckoutCard />}
        </div>
      </div>
    </div>
  );
}
