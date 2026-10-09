// 文件职责：实现 React host renderer，其 “DOM” 是一棵交给 Swift 原生渲染的纯 JSON 树（Raycast 组件运行时）。
// 分层：运行时模块（Raycast JS runtime）；只负责把 React 元素树序列化给 Swift，不直接触碰 AppKit/SwiftUI。
//
// 两条约定让 Raycast 的组件能力得以表达：
//   * `__slot` 实例会把子节点按名字折叠进父级 props，使元素型 props（`actions={<ActionPanel/>}`、
//     `detail={<List.Item.Detail/>}`）以结构形式到达 Swift。
//   * 函数型 props 变成 `{"$fn": "<nodeId>:<propName>"}` 句柄；Swift 通过 id 回调它们。

import Reconciler from "react-reconciler";
import { DefaultEventPriority } from "react-reconciler/constants";
import { reportUncaught } from "./polyfills.js";

/// slot 节点的类型标识：它不会成为独立节点，而是把子节点折叠为父级的具名 prop。
export const SLOT_TYPE = "__slot";

let nextInstanceId = 1;

/// 创建内部树节点：自有自增 id、类型、props 与子节点列表。
function createNode(type, props) {
  return { id: nextInstanceId++, type, props: props ?? {}, children: [] };
}

/// react-reconciler 的 host config：将 React 的树操作映射为纯 JSON 节点的增删改。
const hostConfig = {
  supportsMutation: true,
  supportsPersistence: false,
  supportsHydration: false,
  isPrimaryRenderer: true,
  noTimeout: -1,
  warnsIfNotActing: false,

  getRootHostContext: () => null,
  getChildHostContext: (parentContext) => parentContext,
  getPublicInstance: (instance) => instance,

  createInstance: (type, props) => createNode(type, props),
  createTextInstance: (text) => ({ id: nextInstanceId++, type: "#text", text, children: [] }),

  appendInitialChild: (parent, child) => parent.children.push(child),
  appendChild: (parent, child) => {
    detach(parent, child);
    parent.children.push(child);
  },
  appendChildToContainer: (container, child) => {
    detach(container, child);
    container.children.push(child);
  },
  insertBefore: (parent, child, before) => insert(parent, child, before),
  insertInContainerBefore: (container, child, before) => insert(container, child, before),
  removeChild: (parent, child) => detach(parent, child),
  removeChildFromContainer: (container, child) => detach(container, child),
  clearContainer: (container) => {
    container.children.length = 0;
  },

  finalizeInitialChildren: () => false,
  shouldSetTextContent: () => false,
  commitUpdate: (instance, type, prevProps, nextProps) => {
    instance.props = nextProps;
  },
  commitTextUpdate: (instance, prev, next) => {
    instance.text = next;
  },
  commitMount: () => {},
  resetTextContent: () => {},

  prepareForCommit: () => null,
  resetAfterCommit: (container) => container.onCommit(),
  preparePortalMount: () => {},
  detachDeletedInstance: () => {},

  scheduleTimeout: (fn, delay) => setTimeout(fn, delay),
  cancelTimeout: (handle) => clearTimeout(handle),

  // React 19 的更新优先级钩子：单 surface 渲染器没有需要区分的事件 lane。
  getCurrentUpdatePriority: () => DefaultEventPriority,
  setCurrentUpdatePriority: () => {},
  resolveUpdatePriority: () => DefaultEventPriority,
  getCurrentEventPriority: () => DefaultEventPriority,
  shouldAttemptEagerTransition: () => false,
  requestPostPaintCallback: () => {},
  trackSchedulerEvent: () => {},
  resolveEventType: () => null,
  resolveEventTimeStamp: () => -1.1,
  maySuspendCommit: () => false,
  preloadInstance: () => true,
  startSuspendingCommit: () => {},
  suspendInstance: () => {},
  waitForCommitToBeReady: () => null,
  NotPendingTransition: null,
  HostTransitionContext: {
    $$typeof: Symbol.for("react.context"),
    Provider: null,
    Consumer: null,
    _currentValue: null,
    _currentValue2: null,
    _threadCount: 0,
  },
  resetFormInstance: () => {},
  bindToConsole: (method, args) => () => method.apply(console, args),

  beforeActiveInstanceBlur: () => {},
  afterActiveInstanceBlur: () => {},
  prepareScopeUpdate: () => {},
  getInstanceFromScope: () => null,
  getInstanceFromNode: () => null,
};

/// 合并单一 slot（`detail`、`actions` 等）期望单个元素，但作为 prop 传入的 Fragment
/// （`detail={<><List.Item.Detail markdown={…} /><List.Item.Detail metadata={…} /></>}`）在 reconciler 提交时
/// 会被展平为多个同类型兄弟节点——只保留第一个会静默丢弃其余内容。因此这里改为把同类型兄弟节点合并为
/// 一个节点；异构 Fragment 则退回到取第一个元素，与之前的行为一致。
function mergeSingleSlot(contents) {
  if (contents.length === 1) return contents[0];
  const [first, ...rest] = contents;
  if (rest.some((node) => node.type !== first.type)) return first;
  const merged = { id: first.id, type: first.type, props: { ...first.props }, children: [...first.children] };
  for (const node of rest) {
    Object.assign(merged.props, node.props);
    merged.children.push(...node.children);
  }
  return merged;
}

/// 从父节点的 children 中移除指定子节点（不存在则忽略）。
function detach(parent, child) {
  const index = parent.children.indexOf(child);
  if (index >= 0) parent.children.splice(index, 1);
}

/// 把子节点插入到 `before` 之前；`before` 不存在时追加到末尾。
function insert(parent, child, before) {
  detach(parent, child);
  const index = parent.children.indexOf(before);
  if (index < 0) parent.children.push(child);
  else parent.children.splice(index, 0, child);
}

const reconciler = Reconciler(hostConfig);

/// 一个已挂载的命令。每次 commit 后以序列化后的树触发 `onTree`；handler 查找走 `handlers`，
/// 它在每次序列化时重建，因此一次 dispatch 总是命中最新一次 render 的回调。
export class Surface {
  constructor(onTree, onError) {
    this.handlers = new Map();
    this.onTree = onTree;
    this.onError = onError;
    this.container = { id: 0, type: "#root", props: {}, children: [], onCommit: () => this.flush() };
    this.root = reconciler.createContainer(
      this.container,
      0, // LegacyRoot — 扩展从不启用 concurrent-only 行为
      null,
      false,
      null,
      "gearmac",
      (error) => this.onError(error),
      (error) => this.onError(error),
      (error) => this.onError(error),
      null,
    );
  }

  render(element) {
    reconciler.updateContainer(element, this.root, null, null);
  }

  unmount() {
    try {
      reconciler.updateContainer(null, this.root, null, null);
    } catch (error) {
      reportUncaught(error);
    }
    this.handlers.clear();
  }

  flush() {
    this.handlers.clear();
    const children = this.container.children.map((child) => this.serialize(child)).filter(Boolean);
    this.onTree({ children });
  }

  dispatch(handlerId, args, onComplete) {
    const handler = this.handlers.get(handlerId);
    if (!handler) return false;
    Promise.resolve(handler(...args)).then(() => onComplete?.(), (error) => this.onError(error));
    return true;
  }

  serialize(node) {
    if (node.type === "#text") return { type: "#text", text: String(node.text) };

    const props = {};
    for (const key of Object.keys(node.props)) {
      if (key === "children") continue;
      const value = this.encode(node.props[key], node.id, key);
      if (value !== undefined) props[key] = value;
    }

    const children = [];
    for (const child of node.children) {
      // slot 子节点是父级的结构信息，而不是独立的行。
      if (child.type === SLOT_TYPE) {
        const name = child.props?.name;
        if (!name) continue;
        const contents = child.children.map((entry) => this.serialize(entry)).filter(Boolean);
        if (contents.length) props[name] = child.props.single ? mergeSingleSlot(contents) : contents;
        continue;
      }
      const serialized = this.serialize(child);
      if (serialized) children.push(serialized);
    }

    return { id: node.id, type: node.type, props, children };
  }

  /// 对 prop 取值做 JSON 安全编码。函数变成可 dispatch 的句柄；Date 保留其类型，
  /// 以便 Swift 能往返处理 Form.DatePicker 的值。
  encode(value, nodeId, key) {
    if (value === undefined || value === null) return value === null ? null : undefined;
    switch (typeof value) {
      case "function": {
        const handlerId = `${nodeId}:${key}`;
        this.handlers.set(handlerId, value);
        return { $fn: handlerId };
      }
      case "string":
      case "number":
      case "boolean":
        return value;
      case "bigint":
        return Number(value);
      case "symbol":
        return undefined;
      default:
        break;
    }
    if (value instanceof Date) return { $date: value.toISOString() };
    if (Array.isArray(value)) {
      return value.map((item, index) => this.encode(item, nodeId, `${key}.${index}`) ?? null);
    }
    // 以普通 prop 形式（而非通过 slot）到达的 React 元素无法渲染；直接丢弃，
    // 而不是把 React 内部结构序列化出去。
    if (value.$$typeof) return undefined;
    const out = {};
    for (const name of Object.keys(value)) {
      const encoded = this.encode(value[name], nodeId, `${key}.${name}`);
      if (encoded !== undefined) out[name] = encoded;
    }
    return out;
  }
}

/// 同步刷新 React 工作；底层没有 flushSyncWork 时直接执行回调。
export function flushSync(fn) {
  return reconciler.flushSyncWork ? reconciler.flushSyncWork(fn) : fn?.();
}

/// 测试用的批处理入口，目前直接执行回调。
export function actBatch(fn) {
  return fn();
}
