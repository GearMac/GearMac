"use client";

// 文件职责：复制按钮，把传入的文本写入剪贴板，并在短时间内把图标切为“已复制”。
// 分层：UI（"use client" 客户端组件）；样式由调用方传入，因为它既出现在常暗终端也出现在主题化页面。

import { Check, Copy } from "lucide-react";
import { useState } from "react";
import { cn } from "../../lib/cn";

// “已复制”状态持续多久（毫秒）。
const copiedResetMs = 1600;

// 复制 `text` 并短暂提示已复制。样式由调用方决定，因为它既出现在常暗终端，也出现在主题化页面。
export function CopyButton({
  text,
  className,
}: {
  text: string;
  className?: string;
}) {
  const [hasCopied, setHasCopied] = useState(false);

  async function copy() {
    try {
      await navigator.clipboard.writeText(text);
      setHasCopied(true);
      setTimeout(() => setHasCopied(false), copiedResetMs);
    } catch (error) {
      // 非安全上下文或权限被拒时会走到这里。命令仍留在屏幕上供手动选择，因此记一条日志就够。
      console.warn("Copy to clipboard failed", error);
    }
  }

  return (
    <button
      type="button"
      onClick={copy}
      aria-label={hasCopied ? "Copied" : "Copy command"}
      className={cn(
        "inline-flex h-7 items-center gap-1.5 rounded-full px-2.5 text-caption font-medium transition-colors",
        className,
      )}
    >
      {hasCopied ? (
        <Check size={13} strokeWidth={2.4} className="text-violet-bright" />
      ) : (
        <Copy size={13} strokeWidth={2} />
      )}
      {hasCopied ? "Copied" : "Copy"}
    </button>
  );
}
