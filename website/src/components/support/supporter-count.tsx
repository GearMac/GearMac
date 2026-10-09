"use client";

// 文件职责：展示已付费支持者数量的小徽标，数据来自 Worker 的 /api/supporters。
// 分层：UI（"use client" 客户端组件）；拿不到数据或数量为 0 时完全不渲染。

import { useEffect, useState } from "react";
import { SupportIcon } from "../ui/icon";

/** 已付费支持者的人数，来自 Worker；在拿到数据前不渲染任何内容。 */
export function SupporterCount() {
  const [total, setTotal] = useState(0);

  useEffect(() => {
    const controller = new AbortController();
    fetch("/api/supporters", { signal: controller.signal })
      .then((res) => (res.ok ? res.json() : null))
      .then((body: { total?: number } | null) => setTotal(body?.total ?? 0))
      .catch(() => {});
    return () => controller.abort();
  }, []);

  if (total === 0) return null;
  return (
    <p className="rise mt-6 inline-flex h-8 items-center gap-2 rounded-full bg-kbd-bg px-3.5 text-small text-kbd">
      <SupportIcon size={16} />
      <span>
        Purchased by{" "}
        <span className="font-mono font-medium">
          {total.toLocaleString("en")}
        </span>{" "}
        {total === 1 ? "person" : "people"}
      </span>
    </p>
  );
}
