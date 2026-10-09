"use client";

// 文件职责：静态搜索对话框，在浏览器端用本地索引用 orama 执行检索。
// 分层：网站 UI 组件（客户端）；索引来自 /api/search 静态文件，无服务端搜索。
import { useDocsSearch } from "fumadocs-core/search/client";
import { staticClient } from "fumadocs-core/search/client/orama-static";
import {
  SearchDialog,
  SearchDialogClose,
  SearchDialogContent,
  SearchDialogHeader,
  SearchDialogIcon,
  SearchDialogInput,
  SearchDialogList,
  SearchDialogOverlay,
  type SharedProps,
} from "fumadocs-ui/components/dialog/search";
import { useMemo } from "react";

// 静态搜索：整份索引作为文件下发，查询在浏览器里执行，
// 因为静态导出在服务端没有任何东西可问。
// 静态搜索对话框：把 orama 静态客户端接入 fumadocs 的搜索组件。
export default function StaticSearchDialog(props: SharedProps) {
  const client = useMemo(() => staticClient({ from: "/api/search" }), []);
  const { search, setSearch, query } = useDocsSearch({ client });

  return (
    <SearchDialog
      search={search}
      onSearchChange={setSearch}
      isLoading={query.isLoading}
      {...props}
    >
      <SearchDialogOverlay />
      <SearchDialogContent>
        <SearchDialogHeader>
          <SearchDialogIcon />
          <SearchDialogInput />
          <SearchDialogClose />
        </SearchDialogHeader>
        <SearchDialogList items={query.data !== "empty" ? query.data : null} />
      </SearchDialogContent>
    </SearchDialog>
  );
}
