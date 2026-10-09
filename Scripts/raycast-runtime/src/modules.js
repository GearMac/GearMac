// 文件职责：为扩展 bundle 提供 `require` 实现，把 bundle 外部化的依赖解析到已注册模块。
// 分层：Raycast 运行时（模块加载）；只按注册表解析依赖，不做沙箱隔离。
// 扩展 bundle 看到的 `require`。bundle 是单文件 CJS，只把 `react`、`react/jsx-runtime`、
// `@raycast/api` 和 Node 内置模块留作 external——正好是下面注册的这一组。

import { nodeModules } from "./node-shims.js";

// 模块名 → 导出对象。
const registry = new Map();

/// 注册一个可供扩展 require 的模块。
export function defineModule(name, exports) {
  registry.set(name, exports);
}

// 把所有 Node 内置模块垫片注册进来。
for (const name of Object.keys(nodeModules)) defineModule(name, nodeModules[name]);

/// 扩展实际调用的 `require`：先精确匹配，再回退到包根，最后抛出模块缺失错误。
export function requireModule(name) {
  const key = String(name);
  if (registry.has(key)) return registry.get(key);
  // 对已提供包的深层导入（如 `react-dom/client`）解析到包本身而不是直接报错，
  // 这对少数防御性引用它们的 bundle 已经足够。
  const root = key.startsWith("@") ? key.split("/").slice(0, 2).join("/") : key.split("/")[0];
  if (registry.has(root)) return registry.get(root);
  throw new Error(
    `Cannot find module '${key}'. GearMac provides React, @raycast/api and a subset of Node builtins — see docs/extensions.md.`,
  );
}

/// 执行一个 CJS bundle。`filename`/`dirname` 很关键：扩展会相对 `__dirname` 解析随包资源，
/// 而 `environment.assetsPath` 指向同一目录。
export function evaluateCommonJS(code, filename, dirname) {
  const module = { exports: {}, id: filename, filename, loaded: false, children: [], paths: [] };
  const factory = globalThis.__gearmacCompile(code, filename);
  factory(module.exports, requireModule, module, filename, dirname);
  module.loaded = true;
  return module.exports;
}
