// 文件职责：fumadocs-mdx 配置，定义 docs 集合与 Markdown 渲染管线（rehype-raw、代码高亮语言与主题）。
// 分层：网站构建配置；docs 内容目录固定为 content/docs，高亮仅支持文档实际使用的语言。
import { defineConfig, defineDocs } from "fumadocs-mdx/config";
import rehypeRaw from "rehype-raw";

// fumadocs 注入到语法树中的节点类型，rehype-raw 不得触碰它们。
const MDX_NODES = [
  "mdxjsEsm",
  "mdxFlowExpression",
  "mdxTextExpression",
  "mdxJsxFlowElement",
  "mdxJsxTextElement",
];

// 定义 docs 内容集合，扫描目录为 content/docs。
export const docs = defineDocs({
  dir: "content/docs",
});

export default defineConfig({
  mdxOptions: {
    // 文档是纯 Markdown，默认会丢弃内联 HTML——
    // 这曾静默吞掉快捷键表格里所有 <kbd>。把它重新解析进语法树，
    // 组件映射才能为这些键渲染样式。
    rehypePlugins: (plugins) => [
      // 必须传入 `passThrough`：fumadocs 会向语法树注入 MDX 节点，
      // 若不明确保留，rehype-raw 会拒绝编译它们。
      [rehypeRaw, { passThrough: MDX_NODES }],
      ...plugins,
    ],
    rehypeCodeOptions: {
      // 只保留文档实际用到的语言。每多一种语法都是构建中的纯负担，
      // 且高亮在此处完成，绝不在浏览器里运行。
      langs: ["bash", "json", "markdown"],
      themes: { light: "github-light", dark: "github-dark" },
    },
  },
});
