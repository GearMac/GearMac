// 文件职责：把 Raycast 扩展里的 async 组件适配成 React 可渲染的普通组件，并缓存适配结果。
// 分层：Raycast 运行时（React 适配层）；只处理组件类型，不涉及宿主调用或网络。
// Raycast 扩展会渲染 async 组件（`withAccessToken` 把包装后的命令直接交给 `jsx`），而 React 只在并发路径上
// 重放这类组件——此时它挂起的 thenable 会跨这次尝试存活。同步渲染会丢弃它，导致每次重试都挂到新的 promise 上（#519）。

import { use, useRef, useState } from "react";

// 组件类型 → 适配后组件的缓存，避免每次渲染都重新包装。
const components = new WeakMap();

/// 解析传入的组件类型：async 函数包装为可渲染组件，其余类型原样返回。
export function resolveComponent(type) {
  if (typeof type !== "function") return type;
  let component = components.get(type);
  if (component === undefined) {
    component = type.constructor?.name === "AsyncFunction" ? adapt(type) : type;
    components.set(type, component);
  }
  return component;
}

/// 首渲染不提交任何内容是保住 `type` 挂载时 hooks 的关键：卸载一个从未提交过的 fiber 会丢弃其自身树闭包持有的状态。
function adapt(type) {
  /// 适配后的函数组件：首渲染返回 null 并等待 promise，之后复用同一个 thenable 交给 `use`。
  const component = (props) => {
    const [mounted, setMounted] = useState(false);
    const pending = useRef(null);
    const next = Promise.resolve(type(props));
    if (!mounted) {
      const ready = () => setMounted(true);
      next.then(ready, ready);
      return null;
    }
    // 已有挂起 promise 时复用它，避免同一轮挂起被换成新的 thenable；新 promise 的拒绝被吞掉以免产生未处理 rejection。
    if (pending.current === null) pending.current = next;
    else next.catch(() => {});
    const children = use(pending.current);
    pending.current = null;
    return children;
  };
  return component;
}
