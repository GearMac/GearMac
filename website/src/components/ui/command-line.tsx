// 文件职责：带复制按钮的单行 shell 命令展示，用于首屏的安装 CTA。
// 分层：UI（纯展示组件）；频道切换与 DMG 兜底仍由完整的 Install 区块负责。

import { CopyButton } from "./copy-button";

// 单行 shell 命令加自己的复制按钮 —— 首屏的安装 CTA。
// 整页的 Install 区块仍拥有频道 tab 与 DMG 兜底入口。
export function CommandLine({ command }: { command: string }) {
  return (
    <div className="flex items-center gap-3 rounded-xl border border-border bg-well py-1.5 pl-3.5 pr-1.5">
      <span
        aria-hidden="true"
        className="select-none font-mono text-small text-violet-bright"
      >
        $
      </span>
      <code className="min-w-0 flex-1 overflow-x-auto whitespace-pre font-mono text-small text-fg">
        {command}
      </code>
      <CopyButton
        text={command}
        className="text-fg-muted hover:bg-tint/5 hover:text-fg"
      />
    </div>
  );
}
