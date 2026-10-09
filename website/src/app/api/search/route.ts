// 文件职责：搜索接口，把文档索引以静态文件形式导出，供浏览器端执行检索。
// 分层：网站路由层；导出为 staticGET，构建期产出静态索引。
import { createFromSource } from "fumadocs-core/search/server";
import { source } from "../../../lib/source";

// 索引在构建期输出为静态文件——本站是静态导出，没有服务器可跑搜索路由，
// 因此 `staticGET` 是唯一可行的形态。
export const revalidate = false;
export const { staticGET: GET } = createFromSource(source);
