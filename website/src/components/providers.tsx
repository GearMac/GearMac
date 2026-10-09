"use client";

// 文件职责：全局 Provider，仅挂载 next-themes 主题上下文。
// 分层：网站 UI 组件（客户端）；fumadocs RootProvider 只在文档布局挂载，营销页不承担其开销。
import { ThemeProvider } from "next-themes";
import type { ReactNode } from "react";

// 只有主题是全局的。fumadocs 自己的 RootProvider（会引入搜索上下文及其对话框）
// 改在文档布局里挂载，使营销页永不为它用不到的东西付费。
// 全局 Providers：默认深色主题，跟随系统并禁用切换过渡。
export function Providers({ children }: { children: ReactNode }) {
  return (
    <ThemeProvider
      attribute="class"
      defaultTheme="dark"
      enableSystem
      disableTransitionOnChange
    >
      {children}
    </ThemeProvider>
  );
}
