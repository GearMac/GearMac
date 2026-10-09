"use client";

// 文件职责：文档区 Provider，用 fumadocs RootProvider 提供搜索上下文并按需加载搜索对话框。
// 分层：网站 UI 组件（客户端）；主题由根布局的 next-themes 统一管理，此处禁用以免冲突。
import { RootProvider } from "fumadocs-ui/provider/next";
import dynamic from "next/dynamic";
import type { ReactNode } from "react";

// 按需加载：在真正打开对话框之前，搜索索引与其客户端都是纯负担。
const SearchDialog = dynamic(() => import("./search-dialog"));

// 属于客户端组件，因为对话框以组件引用传递，服务端组件无法跨边界传递它。
// 文档区 Provider：接管搜索，关闭自带主题以避与根布局的 next-themes 冲突。
export function DocsProvider({ children }: { children: ReactNode }) {
  return (
    // `theme.enabled: false`——根布局已接管 next-themes，
    // 第二个 provider 会就 <html> 上的 class 与之冲突。
    <RootProvider search={{ SearchDialog }} theme={{ enabled: false }}>
      {children}
    </RootProvider>
  );
}
