// 文件职责：实现 @raycast/api 的非可视化部分：剪贴板、本地存储、Cache、偏好、应用查询以及窗口/反馈调用。
// 分层：运行时 shim（JS）；这里的一切都是交给 Swift 主 actor 响应的异步 hostCall。

import { hostCall } from "../host.js";
import { nestedEnums } from "./enums.generated.js";

const ToastStyle = nestedEnums.Toast.Style;

let boot = { environment: {}, preferences: {}, launchProps: {} };

/// 由运行时入口注入启动信息（environment / preferences / launchProps 等）。
export function configureSystem(info) {
  boot = { ...boot, ...info };
}

/// GearMac 尚未支持的 API 统一返回一个带有明确原因的 rejected Promise。
export function unsupported(what) {
  return Promise.reject(
    new Error(`${what} is not supported in GearMac extensions yet. See docs/extensions.md.`),
  );
}

// ─── 剪贴板 ─────────────────────────────────────────────────────────

export const Clipboard = {
  copy: (content, options) => hostCall("clipboard", "copy", [normalizeClipboardContent(content), options ?? {}]),
  paste: (content) => hostCall("clipboard", "paste", [normalizeClipboardContent(content)]),
  clear: () => hostCall("clipboard", "clear", []),
  read: (options) => hostCall("clipboard", "read", [options ?? {}]),
  readText: (options) => hostCall("clipboard", "readText", [options ?? {}]),
};

/// 把多种入参形态（字符串/数字/对象）归一化成宿主能识别的剪贴板内容。
function normalizeClipboardContent(content) {
  if (content === null || content === undefined) return { text: "" };
  if (typeof content === "string") return { text: content };
  if (typeof content === "number") return { text: String(content) };
  return content;
}

// ─── LocalStorage ───────────────────────────────────────────────────

/// 异步持久化存储，读写都经过宿主。
export const LocalStorage = {
  async getItem(key) {
    const value = await hostCall("storage", "get", [String(key)]);
    return value === null ? undefined : value;
  },
  setItem: (key, value) => hostCall("storage", "set", [String(key), value]),
  removeItem: (key) => hostCall("storage", "remove", [String(key)]),
  clear: () => hostCall("storage", "clear", []),
  allItems: () => hostCall("storage", "all", []),
};

// ─── Cache ──────────────────────────────────────────────────────────
// Raycast 的 Cache 是同步的。Swift 在构造时就把整个命名空间交给 JS，之后每次写入都是
// fire-and-forget 的写回（write-behind），因此读取能保持 API 要求的同步语义。

const cacheSubscribers = new Map();
let nextCacheSubscription = 1;

/// 同步缓存命名空间：内存副本即时生效，写入异步回写宿主。
export class Cache {
  constructor(options = {}) {
    this.namespace = options.namespace ?? "default";
    this.capacity = options.capacity ?? 10 * 1024 * 1024;
    this._entries = new Map(Object.entries(cacheSnapshot(this.namespace)));
    this._subscribers = new Set();
    // `useCachedState` 会把 `cache.subscribe` 原样（未绑定实例）交给 `useSyncExternalStore`，
    // 因此每个方法都必须能在脱离实例后照常工作。
    for (const method of ["has", "get", "set", "remove", "clear", "subscribe"]) {
      this[method] = Cache.prototype[method].bind(this);
    }
  }

  get isEmpty() {
    return this._entries.size === 0;
  }

  has(key) {
    return this._entries.has(String(key));
  }

  get(key) {
    return this._entries.get(String(key));
  }

  set(key, data) {
    this._entries.set(String(key), String(data));
    this._persist(String(key), String(data));
    this._notify(String(key), String(data));
  }

  remove(key) {
    const existed = this._entries.delete(String(key));
    if (existed) {
      this._persist(String(key), null);
      this._notify(String(key), undefined);
    }
    return existed;
  }

/// 清空当前命名空间；默认会提醒订阅者（notifySubscribers !== false）。
  clear(options = {}) {
    this._entries.clear();
    hostCall("cache", "clear", [this.namespace]).catch(() => {});
    if (options.notifySubscribers !== false) this._notify(undefined, undefined);
  }

/// 订阅缓存变更，返回取消订阅的函数。
  subscribe(subscriber) {
    const id = nextCacheSubscription++;
    this._subscribers.add(subscriber);
    cacheSubscribers.set(id, { namespace: this.namespace, subscriber });
    return () => {
      this._subscribers.delete(subscriber);
      cacheSubscribers.delete(id);
    };
  }

  /// 将条目异步回写到宿主，失败不影响内存副本。
  _persist(key, value) {
    hostCall("cache", "set", [this.namespace, key, value]).catch(() => {});
  }

  /// 通知所有订阅者；单个订阅者抛错不能影响触发它的那次写入。
  _notify(key, data) {
    for (const subscriber of this._subscribers) {
      try {
        subscriber(key, data);
      } catch {
        // 订阅者抛错不能影响触发它的那次写入，这里直接吞掉异常。
      }
    }
  }
}

/// Swift 在启动时安装每个 cache 命名空间的初始内容；启动后才首次访问的命名空间从空开始，随扩展写入而填充。
function cacheSnapshot(namespace) {
  return boot.caches?.[namespace] ?? {};
}

// ─── 偏好设置与环境 ─────────────────────────────────────────────────

/// 返回当前 command 的偏好设置副本。
export function getPreferenceValues() {
  return { ...boot.preferences };
}

/// 环境信息代理：转发到启动时注入的 environment，并补充 `canAccess`（GearMac 里恒为 false）。
export const environment = new Proxy(
  {},
  {
    get(_target, key) {
      if (key === "canAccess") return () => false;
      return boot.environment?.[key];
    },
    has: (_target, key) => key in (boot.environment ?? {}),
    ownKeys: () => Object.keys(boot.environment ?? {}),
    getOwnPropertyDescriptor: () => ({ enumerable: true, configurable: true }),
  },
);

/// 打开本扩展的偏好设置。
export function openExtensionPreferences() {
  return hostCall("window", "openPreferences", ["extension"]);
}

/// 打开当前 command 的偏好设置。
export function openCommandPreferences() {
  return hostCall("window", "openPreferences", ["command"]);
}

// ─── 窗口 / 导航控制 ────────────────────────────────────────────────

/// 关闭主窗口（启动器窗口会在执行 action 后自行收起）。
export function closeMainWindow(options = {}) {
  return hostCall("window", "close", [options]);
}

/// 让导航栈回到根视图。
export function popToRoot(options = {}) {
  return hostCall("window", "popToRoot", [options]);
}

/// 清空搜索栏文本。
export function clearSearchBar(options = {}) {
  return hostCall("window", "clearSearchBar", [options]);
}

// ─── 应用与文件 ─────────────────────────────────────────────────────

/// 用默认或指定应用打开目标（URL / 文件路径）。
export function open(target, application) {
  const app = typeof application === "string" ? application : application?.bundleId ?? application?.path;
  return hostCall("system", "open", [String(target), app ?? null]);
}

/// Raycast 的 Action.OpenWith 会弹出应用选择器；GearMac 由 Swift 找出候选应用并展示。
export function openWith(path) {
  return hostCall("system", "openWith", [String(path)]);
}

export function trash(paths) {
  return hostCall("system", "trash", [(Array.isArray(paths) ? paths : [paths]).map(String)]);
}

export function showInFinder(path) {
  return hostCall("system", "showInFinder", [String(path)]);
}

export function getApplications(path) {
  return hostCall("system", "applications", [path ? String(path) : null]);
}

export function getDefaultApplication(path) {
  return hostCall("system", "defaultApplication", [String(path)]);
}

export function getFrontmostApplication() {
  return hostCall("system", "frontmostApplication", []);
}

export function getSelectedText() {
  return hostCall("system", "selectedText", []);
}

export function getSelectedFinderItems() {
  return hostCall("system", "selectedFinderItems", []);
}

export function captureException(error) {
  console.error(error instanceof Error ? error.stack || error.message : String(error));
}

export function launchCommand(options) {
  return hostCall("system", "launchCommand", [options]);
}

export function updateCommandMetadata(metadata) {
  return hostCall("system", "updateCommandMetadata", [metadata]);
}

export function getFrontmostBrowserTab() {
  return unsupported("getFrontmostBrowserTab");
}

// ─── 反馈 ───────────────────────────────────────────────────────────

/// Toast 对象：属性变更会同步到已展示的宿主 toast。
export class Toast {
  constructor(options = {}) {
    this._id = null;
    this._options = {
      style: options.style ?? ToastStyle.Success,
      title: options.title ?? "",
      message: options.message,
      primaryAction: options.primaryAction,
      secondaryAction: options.secondaryAction,
    };
  }

  get style() {
    return this._options.style;
  }
  set style(value) {
    this._options.style = value;
    this._sync();
  }
  get title() {
    return this._options.title;
  }
  set title(value) {
    this._options.title = value;
    this._sync();
  }
  get message() {
    return this._options.message;
  }
  set message(value) {
    this._options.message = value;
    this._sync();
  }
  get primaryAction() {
    return this._options.primaryAction;
  }
  set primaryAction(value) {
    this._options.primaryAction = value;
    this._sync();
  }
  get secondaryAction() {
    return this._options.secondaryAction;
  }
  set secondaryAction(value) {
    this._options.secondaryAction = value;
    this._sync();
  }

  async show() {
    this._id = await hostCall("feedback", "showToast", [this._serialize()]);
    return this;
  }

  async hide() {
    if (this._id === null) return;
    await hostCall("feedback", "hideToast", [this._id]);
    this._id = null;
  }

  _sync() {
    if (this._id === null) return;
    hostCall("feedback", "updateToast", [this._id, this._serialize()]).catch(() => {});
  }

  /// Toast 的 action 携带回调，无法跨桥传递。因此在本地登记回调，只发送标题和一个 token，
  /// 由 Swift 通过 `runToastAction` 回传该 token。
  _serialize() {
    const encode = (action, slotName) => {
      if (!action) return null;
      const token = `${this._token()}:${slotName}`;
      toastActions.set(token, action.onAction);
      return { title: action.title, shortcut: action.shortcut, token };
    };
    return {
      style: this._options.style,
      title: this._options.title,
      message: this._options.message,
      primaryAction: encode(this._options.primaryAction, "primary"),
      secondaryAction: encode(this._options.secondaryAction, "secondary"),
    };
  }

  _token() {
    if (!this._tokenBase) this._tokenBase = `toast-${nextToastToken++}`;
    return this._tokenBase;
  }
}

Toast.Style = ToastStyle;

let nextToastToken = 1;
const toastActions = new Map();

/// 由宿主根据 token 回调对应的 toast action。
export function runToastAction(token) {
  const handler = toastActions.get(token);
  if (!handler) return;
  // Raycast 会把当前的 Toast 实例传给回调；这里的 shim 只传一个带 token 的占位对象。
  handler({ hide: () => {} });
}

/// 显示 toast；既支持 `showToast(options)` 也支持 `showToast(style, title, message)`。
export async function showToast(optionsOrStyle, title, message) {
  const options =
    typeof optionsOrStyle === "object" && optionsOrStyle !== null
      ? optionsOrStyle
      : { style: optionsOrStyle, title, message };
  const toast = new Toast(options);
  await toast.show();
  return toast;
}

/// 在屏幕中央短暂显示一条提示。
export function showHUD(title, options = {}) {
  return hostCall("feedback", "showHUD", [String(title), options]);
}

/// 弹出确认对话框；用户确认后执行 primaryAction，否则执行 dismissAction。
export function confirmAlert(options = {}) {
  return hostCall("feedback", "confirmAlert", [
    {
      title: options.title,
      message: options.message,
      icon: options.icon,
      primaryAction: options.primaryAction ? { title: options.primaryAction.title, style: options.primaryAction.style } : null,
      dismissAction: options.dismissAction ? { title: options.dismissAction.title, style: options.dismissAction.style } : null,
      rememberUserChoice: !!options.rememberUserChoice,
    },
  ]).then((confirmed) => {
    if (confirmed) options.primaryAction?.onAction?.();
    else options.dismissAction?.onAction?.();
    return confirmed;
  });
}

// ─── 旧扩展仍在使用的已废弃别名 ─────────────────────────────────────

export const copyTextToClipboard = Clipboard.copy;
export const pasteText = Clipboard.paste;
export const clearClipboard = Clipboard.clear;
export const getLocalStorageItem = LocalStorage.getItem;
export const setLocalStorageItem = LocalStorage.setItem;
export const removeLocalStorageItem = LocalStorage.removeItem;
export const allLocalStorageItems = LocalStorage.allItems;
export const clearLocalStorage = LocalStorage.clear;
export const randomId = () => `${Date.now().toString(36)}${Math.floor(Math.random() * 1e9).toString(36)}`;
