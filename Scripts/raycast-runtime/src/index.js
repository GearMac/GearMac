// 文件职责：Raycast 运行时入口——安装 polyfill 与模块注册表，暴露 Swift 唯一调用的 `__gearmac`。
// 分层：Raycast 运行时（入口/会话编排）；负责命令生命周期与 UI 事件路由，不直接操作 AppKit。
// 入口点。先安装 polyfill 与模块注册表，再暴露 `__gearmac`——Swift 唯一调用的对象。

import "./polyfills.js";
import "./url.js";
import { createElement } from "react";
import * as React from "react";
import * as JSXRuntime from "react/jsx-runtime";
import { describeError, log, settle } from "./host.js";
import { fireTimer, setUncaughtHandler } from "./polyfills.js";
import { configureNodeShims } from "./node-shims.js";
import { defineModule, evaluateCommonJS } from "./modules.js";
import { resolveComponent } from "./async-component.js";
import { NavigationRoot, setFieldCommandHandler } from "./api/components.js";
import { Surface } from "./reconciler.js";
import { raycastApi } from "./api/index.js";
import { configureSystem, runToastAction } from "./api/system.js";
import { WebSocket } from "./websocket.js";

// 包装 React：让 createElement 先解析 async 组件再创建元素。
const reactModule = {
  ...React,
  createElement: (type, ...rest) => createElement(resolveComponent(type), ...rest),
};
// 同理包装 jsx/jsxs 转换函数。
const jsxModule = {
  ...JSXRuntime,
  jsx: (type, props, key) => JSXRuntime.jsx(resolveComponent(type), props, key),
  jsxs: (type, props, key) => JSXRuntime.jsxs(resolveComponent(type), props, key),
};
// 兼容 default 导入写法。
reactModule.default = reactModule;
jsxModule.default = jsxModule;

// 注册扩展 bundle 可直接 require 的模块。
defineModule("react", reactModule);
defineModule("react/jsx-runtime", jsxModule);
defineModule("react/jsx-dev-runtime", jsxModule);
defineModule("@raycast/api", raycastApi);
// react-dom 只会出现在防御性引用它的 bundle 里：让导入能解析，调用时给出说明即可。
defineModule("react-dom", {
  render: () => {
    throw new Error("react-dom is not available — GearMac renders extensions natively.");
  },
  createPortal: (children) => children,
  flushSync: (fn) => fn?.(),
  version: React.version,
});
// WebSocket 暴露到全局，供扩展直接使用。
globalThis.WebSocket = WebSocket;

// 正在运行的命令会话，按 sessionId 索引。
const sessions = new Map();

/// 一个正在运行的命令：视图命令通过 `Surface` 挂载 React 树，无视图命令只 await 它的默认导出。
class Session {
  constructor(id, host) {
    this.id = id;
    this.host = host;
    this.surface = null;
    this.navigationDepth = 1;
    this.navigation = {};
  }

  /// 挂载视图命令的 React 树，并把导航栈深度变化回传给宿主。
  mountView(element) {
    this.surface = new Surface(
      (tree) => this.host.render(this.id, JSON.stringify(tree)),
      (error) => this.fail(error),
    );
    this.surface.render(
      createElement(NavigationRoot, {
        initial: element,
        controls: this.navigation,
        onStackChange: (depth) => {
          this.navigationDepth = depth;
          this.host.navigationDepthChanged(this.id, depth);
        },
      }),
    );
  }

  /// 把错误上报给 Swift 宿主。
  fail(error) {
    this.host.failed(this.id, describeError(error));
  }

  /// 卸载当前 React 树。
  unmount() {
    this.surface?.unmount();
    this.surface = null;
  }
}


/// 会话回调 Swift 宿主的调用集合。
const hostCalls = {
  render: (sessionId, json) => globalThis.__gearmacHost.render(sessionId, json),
  failed: (sessionId, message) => globalThis.__gearmacHost.failed(sessionId, message),
  navigationDepthChanged: (sessionId, depth) =>
    globalThis.__gearmacHost.navigationDepthChanged(sessionId, String(depth)),
  finished: (sessionId) => globalThis.__gearmacHost.finished(sessionId),
};

// 注册全局未捕获错误处理器：记录日志，并尽量把错误归属到当前会话。
setUncaughtHandler((error) => {
  const message = describeError(error);
  log("error", [message]);
  // 当恰好只有一个会话在运行时，把未处理的 rejection 归属给它，让面板能显示错误而不是静默失败。
  if (sessions.size === 1) {
    const [session] = sessions.values();
    session.fail(error);
  }
});

// 表单字段命令转交 Swift 处理。
setFieldCommandHandler((command, fieldId) => {
  globalThis.__gearmacHost.fieldCommand(String(command), String(fieldId ?? ""));
});

/// Swift 调用的宿主入口对象。
globalThis.__gearmac = {
  /// 在所有命令运行前调用一次，完成运行时配置。
  boot(configJson) {
    const config = JSON.parse(configJson);
    configureNodeShims(config.node ?? {});
    configureSystem(config);
    return "ok";
  },

  // 菜单栏与视图命令挂载组件；无视图命令 await 其默认导出。
  start(sessionId, code, filename, dirname, mode, contextJson) {
    const context = JSON.parse(contextJson || "{}");
    configureSystem(context);
    const session = new Session(sessionId, hostCalls);
    sessions.set(sessionId, session);
    // 声明了 `arguments` 的命令会无保护地读取 `props.arguments.<name>`，因此这个对象始终存在。
    const launchProps = {
      launchType: "userInitiated",
      arguments: {},
      ...(context.launchProps ?? {}),
    };
    try {
      const exports = evaluateCommonJS(code, filename, dirname);
      const entry = exports?.default ?? exports;
      if (mode !== "no-view") {
        if (typeof entry !== "function") {
          throw new Error("A view command must default-export a React component.");
        }
        session.mountView(createElement(resolveComponent(entry), launchProps));
      } else {
        if (typeof entry !== "function") {
          throw new Error("A no-view command must default-export a function.");
        }
        Promise.resolve(entry(launchProps)).then(
          () => hostCalls.finished(sessionId),
          (error) => session.fail(error),
        );
      }
    } catch (error) {
      session.fail(error);
    }
    return "ok";
  },

  /// 把 UI 事件路由回它来源的回调；返回 "1"/"0" 表示是否成功派发。
  dispatch(sessionId, handlerId, argsJson, completesSession = false) {
    const session = sessions.get(sessionId);
    if (!session?.surface) return "0";
    try {
      const args = JSON.parse(argsJson || "[]").map(reviveArg);
      const dispatched = session.surface.dispatch(
        handlerId, args, completesSession ? () => hostCalls.finished(sessionId) : undefined,
      );
      if (!dispatched && completesSession) hostCalls.finished(sessionId);
      return dispatched ? "1" : "0";
    } catch (error) {
      session.fail(error);
      return "0";
    }
  },

  /// 响应被压入栈的界面中的 Escape 或返回箭头。
  popNavigation(sessionId) {
    const session = sessions.get(sessionId);
    if (!session?.surface || session.navigationDepth <= 1) return "0";
    session.navigation.pop?.();
    return "1";
  },

  // 直接转交的宿主/工具函数。
  settle,
  fireTimer,
  runToastAction,

  /// 结束会话：卸载 React 树并从会话表移除。
  stop(sessionId) {
    sessions.get(sessionId)?.unmount();
    sessions.delete(sessionId);
    return "ok";
  },
};

/// `{"$date": …}` 是 Form.DatePicker 的值从 Swift 传回时的表示形式。
function reviveArg(value) {
  if (value && typeof value === "object") {
    if (typeof value.$date === "string") return new Date(value.$date);
    if (Array.isArray(value)) return value.map(reviveArg);
  }
  return value;
}
