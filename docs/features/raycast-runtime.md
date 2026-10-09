# Raycast Runtime 运行时说明

## 1. 这部分代码解决什么问题

`Scripts/raycast-runtime/` 是 GearMac 内置的 Raycast 扩展 JavaScript 运行时源码。

GearMac 不是通过 Electron、浏览器或 Node.js 来运行 Raycast 扩展，而是使用 macOS 自带的
JavaScriptCore 执行扩展代码。Raycast 扩展通常依赖以下能力：

- React 和 `react/jsx-runtime`；
- `@raycast/api` 组件和系统 API；
- Node.js 内置模块，例如 `fs`、`path`、`crypto`、`zlib`；
- 浏览器或 Web API，例如 `URL`、`fetch`、Streams、WebSocket；
- React 的调度器和异步渲染机制。

JavaScriptCore 只提供 JavaScript 引擎本身，不提供完整的 Node.js 或浏览器运行环境。因此，
这个目录实现了一个适配层，把 Raycast 扩展需要的 API 补齐，并把真正需要访问 macOS 系统的操作
转交给 Swift 宿主。

最终关系是：

```text
Raycast 扩展 command.js
        │
        ▼
RaycastRuntime.generated.js
        │
        ├── React / React Reconciler
        ├── @raycast/api shim
        ├── Node.js shim
        ├── Web API polyfill
        └── JavaScript ↔ Swift host bridge
        │
        ▼
JavaScriptCore
        │
        ▼
JSON Render Tree
        │
        ▼
GearMac 的 SwiftUI / AppKit 原生界面
```

它的职责不是实现某一个扩展，而是为所有已安装的 Raycast 扩展提供共同运行环境。

---

## 2. 生成物与源码的关系

源码位于：

```text
Scripts/raycast-runtime/
```

构建后生成：

```text
GearMac//Resources/RaycastRuntime.generated.js
```

`RaycastRuntime.generated.js` 是提交到仓库的生成文件。这样 Xcode 构建 GearMac 时不需要在
每次构建过程中重新安装 Node 依赖或运行 Node 脚本。

不要直接编辑生成文件。正确流程是：

```bash
cd Scripts/raycast-runtime
pnpm install
node gen-enums.mjs
node build.mjs
```

如果要调试未压缩的 runtime，可以使用：

```bash
node build.mjs --dev
```

`build.mjs` 会把 `src/index.js` 及其依赖打包成一个 IIFE 文件，供 Swift 创建的
`JSContext` 加载。

---

## 3. 根目录文件

### 3.1 `build.mjs`

这是 runtime 的打包脚本。

主要工作：

1. 以 `src/index.js` 作为入口；
2. 使用 esbuild 打包所有 JavaScript 依赖；
3. 使用 `es2022` 作为目标版本；
4. 生产模式压缩代码；
5. 把结果写入 `GearMac//Resources/RaycastRuntime.generated.js`；
6. 在输出文件中写入“不要手动修改”的提示。

生产构建默认压缩代码，`--dev` 会关闭压缩，以便调试。

### 3.2 `gen-enums.mjs`

这个脚本从实际安装的 `@raycast/api` 类型定义中提取枚举，并生成：

```text
src/api/enums.generated.js
```

它覆盖的内容包括：

- `Icon`；
- `Color`；
- `Toast.Style`；
- `Action.Style`；
- `Grid.Fit`；
- `Grid.Inset`；
- `Keyboard`；
- `Image.Mask`；
- 其他 Raycast API 枚举。

这样扩展拿到的枚举字符串可以跟官方 `@raycast/api` 保持一致。这个文件也是生成文件，不能
手动编辑。升级 `@raycast/api` 后，应重新执行枚举生成和 runtime 构建。

### 3.3 `test.mjs`

这是 runtime 的通用测试驱动器。

它使用 Node 的 `vm` 创建一个受限 JavaScript 环境，尽量模拟 JavaScriptCore：

- 不直接提供 Node 全局对象；
- 不直接提供浏览器环境；
- 安装假的 `__gearmacHost`；
- 加载真实的 `RaycastRuntime.generated.js`；
- 执行真实的扩展 CommonJS bundle；
- 收集 Swift 侧应该收到的 Render Tree；
- 模拟异步 host 调用和事件分发。

基本用法：

```bash
node test.mjs
```

也可以指定一个扩展目录和命令名称：

```bash
node test.mjs <extension-dir> <command-name>
```

它验证的是 JavaScript runtime、扩展加载和渲染协议，不是最终 Swift UI 的视觉效果。

### 3.4 `fixtures.mjs`

这是内置 fixture 测试集合。

每个 fixture 都是一个小型 Raycast 扩展命令，会被 esbuild 编译成和真实扩展接近的 CommonJS
bundle，然后交给 runtime 执行。它覆盖的场景包括：

- List、Grid、Detail、Form；
- ActionPanel 和 Action 回调；
- 页面导航；
- 异步组件；
- 菜单栏扩展；
- Toast；
- 文件访问；
- 网络请求；
- 定时器；
- 扩展失败和异常报告。

它适合快速验证 runtime 的某个能力是否仍然可用。

### 3.5 `package.json`

定义 runtime 工程的依赖和构建脚本。

关键依赖：

- `react`：运行扩展的 React 组件；
- `react-reconciler`：把 React 树提交给 GearMac 自己的 JSON 渲染器；
- `@raycast/api`：提供官方 API 类型和枚举来源；
- `esbuild`：构建最终单文件 runtime。

### 3.6 `pnpm-lock.yaml`

锁定上述 npm 依赖的具体版本，确保不同机器生成的 runtime 不因为依赖漂移而出现差异。

---

## 4. `src/` 核心运行时文件

### 4.1 `src/index.js`：runtime 总入口

这是整个 JavaScript runtime 的入口，也是 Swift 能够调用的唯一主要入口。

加载后，它会安装：

- JavaScript polyfill；
- URL 实现；
- React 和 JSX runtime；
- Node shim 模块；
- `@raycast/api`；
- React Reconciler；
- WebSocket；
- `__gearmac` 全局对象。

`__gearmac` 的主要方法如下：

| 方法 | 作用 |
| --- | --- |
| `boot` | 初始化 Node 配置、环境变量、偏好设置和系统配置 |
| `start` | 启动一个扩展命令 |
| `dispatch` | 将 Swift UI 触发的事件分发给 JavaScript 回调 |
| `popNavigation` | 返回扩展页面的上一级 |
| `settle` | 完成 Swift 发起的异步 host 调用 |
| `fireTimer` | 触发由 Swift 维护的 JavaScript 定时器 |
| `runToastAction` | 执行 Toast 上的操作按钮 |
| `stop` | 卸载一个扩展会话 |

一个命令对应一个 `Session`。有界面命令会创建 React `Surface` 并挂载组件；无界面命令会调用
默认导出的函数，并等待 Promise 完成。

### 4.2 `src/host.js`：JavaScript 与 Swift 的边界

这里是 JS runtime 和 Swift 宿主之间的唯一通信层。

Swift 会在执行 runtime 之前安装：

```js
globalThis.__gearmacHost
```

JS 侧主要通过两个函数访问它。

#### 异步 host 调用

```js
hostCall(api, method, args)
```

适合访问需要主 actor 或系统服务的功能，例如：

- 剪贴板；
- Toast；
- LocalStorage 和 Cache；
- Preferences；
- `fetch`；
- `exec`；
- OAuth；
- 窗口和系统操作。

调用流程是：

```text
JS hostCall
  ↓
__gearmacHost.invoke
  ↓
Swift 异步处理
  ↓
__gearmac.settle
  ↓
Promise resolve / reject
```

#### 同步 host 调用

```js
hostCallSync(api, method, args)
```

只用于可以在 JS runtime 所在线程直接处理的 Node 兼容能力，例如：

- `fs.readFileSync`；
- `crypto`；
- `zlib`；
- 部分 `os` 和 `child_process` 操作。

同步调用不能接触主 actor，否则可能造成死锁。因此这里必须保持边界清晰。

### 4.3 `src/modules.js`：CommonJS 模块注册器

Raycast 扩展通常是预构建的 CommonJS 文件，里面会保留以下外部模块：

```js
require("react")
require("react/jsx-runtime")
require("@raycast/api")
require("node:fs")
```

GearMac 不运行 Node 的模块加载器，而是通过一个模块注册表提供这些模块：

- `defineModule(name, exports)` 注册模块；
- `requireModule(name)` 查找模块；
- `evaluateCommonJS(...)` 用 CommonJS 参数执行扩展 bundle。

执行扩展时还会传入：

- `exports`；
- `require`；
- `module`；
- `__filename`；
- `__dirname`。

因此扩展中的相对资源路径仍然可以根据扩展目录解析。

### 4.4 `src/reconciler.js`：React 到 JSON Render Tree

GearMac 没有浏览器 DOM。这个文件把 React 的提交过程接到一个自定义 host renderer 上。

扩展写出的组件：

```jsx
<List>
  <List.Item title="Hello" />
</List>
```

会被转换成类似这样的结构：

```json
{
  "type": "List",
  "props": {},
  "children": [
    {
      "type": "List.Item",
      "props": { "title": "Hello" },
      "children": []
    }
  ]
}
```

Swift 侧解码这个结构，并使用 GearMac 自己的原生组件显示它。

#### `__slot`

Raycast 有很多通过 prop 传入 React 元素的 API：

```jsx
<List.Item actions={<ActionPanel />} />
```

普通 React children 不会自动把这个 prop 里的元素作为树节点提交。因此 runtime 用 `__slot`
标记这些特殊结构，再把它们折叠回父节点的 props，使 Swift 能收到完整的 `actions`、`detail`、
`metadata` 或 `searchBarAccessory`。

#### 函数回调句柄

函数 prop 不能直接序列化成 JSON。runtime 会把函数保存到 handler 表中，并序列化成：

```json
{ "$fn": "<nodeId>:<propName>" }
```

Swift 用户点击按钮后，Swift 调用 `__gearmac.dispatch(...)`，runtime 再从最新渲染提交的
handler 表中找到并执行对应回调。

### 4.5 `src/async-component.js`：异步 React 组件适配

Raycast 扩展可以导出异步组件，也可能使用会返回 Promise 的包装器，例如 OAuth 相关的
`withAccessToken`。

React 并发渲染会重复尝试组件。如果每次尝试都创建新的 Promise，组件可能一直 suspend，无法
完成渲染。

这个文件会缓存和包装异步组件，确保同一个渲染过程复用稳定的 thenable。

---

## 5. JavaScriptCore 兼容层

### 5.1 `src/polyfills.js`

JavaScriptCore 提供现代 JavaScript 语言能力，但不是完整浏览器环境。这个文件补齐扩展和 React
调度器常用的全局对象，包括：

- `console`；
- `setTimeout`、`setInterval` 及清理函数；
- `fetch`；
- `AbortController`；
- `Event` 和 `EventTarget`；
- `MessageChannel` 和 `MessagePort`；
- `Blob`、`File`、`FormData`；
- `DOMException`；
- `TextEncoder` 和 `TextDecoder`；
- `atob` 和 `btoa`；
- `structuredClone`；
- 未捕获异常和未处理 Promise rejection 的上报。

这些实现通常会继续通过 `hostCall` 使用 Swift 能力。

### 5.2 `src/url.js`

实现 JavaScriptCore 不自带的：

- `URL`；
- `URLSearchParams`。

它支持扩展常用的 HTTP、HTTPS、WebSocket URL 解析和查询参数操作，但不是完整 WHATWG URL
规范的全部实现。

### 5.3 `src/buffer.js`

提供精简版 Node `Buffer`，底层使用 `Uint8Array`。

支持的典型操作包括：

- UTF-8 编码和解码；
- Base64 编码和解码；
- Hex 编码和解码；
- 二进制片段拼接；
- Buffer 与字符串转换。

它被加密、压缩、WebSocket 和部分网络依赖使用。

### 5.4 `src/events.js`

实现 Node 的 `EventEmitter`，包括：

- `on`；
- `once`；
- `off`；
- `emit`；
- listener 管理。

Streams、WebSocket 和网络适配器都依赖这种事件模型。

### 5.5 `src/streams.js`

实现 Node 风格的流：

- `Readable`；
- `Writable`；
- `Duplex`；
- `Transform`；
- `PassThrough`；
- `Stream`；
- `finished`。

它用于兼容一些会处理大 JSON 或二进制数据的扩展依赖，例如对象模式流和 `stream-json`。

### 5.6 `src/web-streams.js`

实现 WHATWG Web Streams：

- `ReadableStream`；
- `WritableStream`；
- `TransformStream`；
- `getReader`；
- `pipeThrough`；
- `pipeTo`；
- 异步迭代。

它主要适配 `fetch` 的响应体和现代 Web API 风格的数据流。

### 5.7 `src/node-shims.js`

集中注册扩展会使用的 Node 内置模块，包括：

- `path`；
- `fs`；
- `os`；
- `child_process`；
- `crypto`；
- `zlib`；
- `util`；
- `events`；
- `buffer`；
- `stream`；
- `url`；
- `punycode`；
- `dgram`。

这里的重点是“兼容扩展 API”，不是把 Node.js 完整移植进 GearMac。不同模块会根据性质选择：

- JS 内部实现；
- 同步转交 Swift；
- 异步转交 Swift；
- 仅提供模块入口，但在调用不支持的能力时抛出清晰错误。

### 5.8 `src/punycode.js`

实现 Node 的 `punycode`，用于 Unicode 域名和 ASCII 域名之间的转换。

很多网络库会间接依赖它，即使扩展代码本身没有直接导入 `punycode`。

### 5.9 `src/dgram.js`

提供受限的 UDP `dgram` 兼容实现。

GearMac 的用途是支持某些依赖对 `.local` 主机名的 mDNS 查询。它不提供一个完整、任意可用的
UDP 服务端实现，而是把这类查询交给系统解析能力。

### 5.10 `src/websocket.js`

把 JavaScript WebSocket API 连接到 Swift 的 `URLSessionWebSocketTask`。

JS 侧负责 API 形状，Swift 侧负责真正的网络连接、读取和关闭。实现还保证发送操作按顺序排队，
避免多个 host 调用完成顺序不一致。

---

## 6. `src/api/`：Raycast API 兼容层

### 6.1 `src/api/index.js`

组装并导出扩展看到的 `@raycast/api` 模块。

它将以下内容合并到一个 API 表面：

- React 组件；
- 系统 API；
- OAuth；
- 枚举；
- Action；
- Navigation；
- List；
- Grid；
- Form；
- Detail；
- MenuBarExtra。

扩展中的：

```js
import { List, ActionPanel, showToast } from "@raycast/api";
```

最终都从这里解析。

### 6.2 `src/api/components.js`

实现 Raycast 的视觉组件和交互组件，主要包括：

- `List` 和 `List.Item`；
- `Grid` 和 `Grid.Item`；
- `Detail`；
- `Form` 及其字段；
- `ActionPanel` 和 `Action`；
- `MenuBarExtra`；
- `Navigation`；
- `useNavigation`。

这些组件不会直接创建 AppKit 或 SwiftUI 控件，而是创建 runtime 的 React 节点，交给
`reconciler.js` 生成 JSON，再由 Swift 原生层渲染。

### 6.3 `src/api/system.js`

实现 `@raycast/api` 的非视觉部分，包括：

- `Clipboard`；
- `LocalStorage`；
- `Cache`；
- `Toast`；
- `showToast`；
- `open`；
- `showInFinder`；
- `closeMainWindow`；
- `getSelectedText`；
- `getPreferenceValues`；
- `environment`；
- 应用查找和窗口操作。

这部分通常通过 `hostCall` 交给 Swift，因为它们需要访问操作系统、主 actor 或 GearMac 的持久化
服务。

### 6.4 `src/api/oauth.js`

实现 Raycast OAuth API 的 JavaScript 侧协议，包括：

- `OAuth.PKCEClient`；
- `OAuth.TokenSet`；
- code verifier；
- PKCE challenge；
- state；
- redirect URL；
- token 读写。

真正的 Keychain 保存、浏览器打开、回调 URL 处理由 Swift 的 OAuth 服务负责。

### 6.5 `src/api/enums.generated.js`

这是由 `gen-enums.mjs` 生成的枚举文件，保存官方 `@raycast/api` 的字符串值。

例如：

```js
Color.Blue
Toast.Style.Success
Action.Style.Destructive
```

不要直接编辑此文件。需要更新时修改生成来源或依赖版本，再重新生成。

---

## 7. JS 与 Swift 的连接点

JavaScript runtime 的 Swift 宿主位于：

```text
GearMac//Features/Extensions/Service/
```

其中最关键的是：

| Swift 文件 | 作用 |
| --- | --- |
| `ExtensionRuntime.swift` | 创建和管理 `JSContext`，加载生成的 runtime，执行命令 |
| `ExtensionHostBridge.swift` | 提供剪贴板、Storage、Toast、Preferences、窗口、OAuth 等 host API |
| `ExtensionNodeShims.swift` | 提供同步 `fs`、`os`、`crypto`、`zlib`、`child_process` 能力 |
| `ExtensionFetcher.swift` | 提供 fetch、异步 exec 和网络请求处理 |
| `ExtensionWebSocketBridge.swift` | 对接 WebSocket 网络连接 |
| `ExtensionManager.swift` | 管理安装扩展、前台命令、后台刷新和菜单栏命令 |
| `ExtensionScreen.swift` | 把 Render Tree 转为扩展在 palette 中的显示内容 |

### 执行命令

```text
ExtensionRuntime.swift
  ↓ 加载 RaycastRuntime.generated.js
__gearmac.boot(...)
  ↓
__gearmac.start(...)
  ↓
evaluateCommonJS(...)
  ↓
扩展默认导出的组件或函数
```

### 渲染界面

```text
React component
  ↓
react-reconciler
  ↓
Render Tree JSON
  ↓
ExtensionRuntime.swift
  ↓
ExtensionScreen.swift
  ↓
GearMac 原生界面
```

### 处理用户交互

```text
用户点击 Swift 原生 Action
  ↓
Swift 读取 $fn handler 标识
  ↓
__gearmac.dispatch(...)
  ↓
JavaScript 回调执行
  ↓
React 重新提交 Render Tree
```

### 处理系统调用

```text
扩展调用 showToast / Clipboard / fetch
  ↓
api/system.js
  ↓
host.js
  ↓
__gearmacHost.invoke(...)
  ↓
Swift host bridge
  ↓
__gearmac.settle(...)
  ↓
JavaScript Promise 完成
```

---

## 8. 一个扩展命令的完整生命周期

### 8.1 启动 runtime

Swift 创建一个专用 `JSContext`，安装：

```js
globalThis.__gearmacHost
globalThis.__gearmacCompile
```

然后执行生成的 `RaycastRuntime.generated.js`。

### 8.2 调用 `boot`

Swift 将环境信息传给：

```js
__gearmac.boot(configJson)
```

配置可能包括：

- 扩展目录；
- assets 路径；
- 环境变量；
- 用户偏好；
- launch props；
- Node shim 所需的系统配置。

### 8.3 调用 `start`

Swift 传入：

- session ID；
- 扩展 CommonJS 代码；
- 文件名；
- 目录名；
- 命令模式；
- 启动上下文。

runtime 使用 `evaluateCommonJS` 执行代码。

### 8.4 处理两种命令

#### 有界面命令

默认导出的是 React 组件：

```js
export default function Command() {
  return <List />;
}
```

runtime 会挂载 React 树并持续提交 Render Tree。

#### 无界面命令

默认导出的是函数：

```js
export default async function Command() {
  await showToast(...);
}
```

runtime 会执行这个函数，完成后通知 Swift。

### 8.5 停止命令

Swift 调用：

```js
__gearmac.stop(sessionId)
```

runtime 会卸载 React surface，清理该 session，并释放 JavaScript 会话。

GearMac 会丢弃整个 `JSContext`，避免扩展遗留的 timer、React scheduler 或模块级状态污染下一个
命令。

---

## 9. 关键设计点

### 9.1 不使用浏览器 DOM

扩展不是在网页中运行，也没有 HTML DOM。React 只负责生成结构，Swift 负责原生渲染。

因此扩展组件必须先变成可序列化的 Render Tree。

### 9.2 不直接把系统对象暴露给 JavaScript

JavaScript 只能拿到 JSON、字符串、数字、数组、对象以及少量明确的句柄。文件、进程、网络、
Keychain、剪贴板等能力通过 host bridge 调用 Swift。

这样可以控制：

- 线程边界；
- 主 actor 访问；
- 生命周期；
- 错误处理；
- 扩展之间的隔离。

### 9.3 `JSContext` 只在自己的串行队列访问

`ExtensionRuntime` 中的 `JSContext` 和 `JSValue` 不能跨线程随意访问。Swift 侧把它们限制在专用
串行队列中，跨队列只传递：

- JSON 字符串；
- `RenderTree`；
- `RenderValue`；
- 其他普通 `Sendable` 值。

### 9.4 每个命令使用独立会话

一个前台命令启动时，会停止前一个命令并创建新的运行上下文。这样可以避免：

- 上一个扩展的模块级变量残留；
- 未清理的 timer 影响下一个命令；
- React scheduler 状态被旧命令污染；
- 异步 host 回复落到错误的扩展会话。

### 9.5 只实现实际需要的 Node/Web API

这里不是完整 Node.js 移植。每个 shim 都是为了支持真实 Raycast 扩展中出现的依赖。

没有实现或不适合实现的能力，应返回明确错误，而不是静默伪造成功结果。

---

## 10. 构建、测试与生成文件注意事项

### 构建 runtime

```bash
cd Scripts/raycast-runtime
pnpm install
node gen-enums.mjs
node build.mjs
```

### 运行 runtime fixture

```bash
cd Scripts/raycast-runtime
node fixtures.mjs
```

### 执行指定扩展

```bash
cd Scripts/raycast-runtime
node test.mjs <extension-dir> <command-name>
```

### 修改规则

- 修改 runtime 行为时，改 `src/` 下的源码；
- 修改 API 枚举时，重新运行 `gen-enums.mjs`；
- 修改后重新运行 `build.mjs`；
- 提交重新生成的 `GearMac//Resources/RaycastRuntime.generated.js`；
- 不要手动编辑 `RaycastRuntime.generated.js`；
- 不要手动编辑 `src/api/enums.generated.js`；
- 如果扩展依赖了新的 Node 或 Web API，先确认应该由 JS 实现还是由 Swift host 提供；
- 新增 host 调用时，必须同时检查 JS 侧 API、Swift bridge、线程和生命周期边界。

---

## 11. 能力边界

这个 runtime 的目标是运行常见的 Raycast 扩展，而不是保证所有 Raycast 服务都能在 GearMac 中
完全等价运行。

以下能力依赖 GearMac 是否有对应的 Swift 实现：

- 剪贴板；
- 本地存储和缓存；
- Toast；
- 文件系统；
- 进程执行；
- fetch；
- WebSocket；
- OAuth；
- 窗口和应用控制。

某些 Raycast 专属云服务或 GearMac 没有本地等价物的能力会明确返回“不支持”，而不是假装完成。
实际支持范围应以 `docs/features/extensions.md` 中的支持矩阵为准。

---

## 12. 一句话总结

`Scripts/raycast-runtime` 是 GearMac 的“Raycast 扩展执行层”：它在 JavaScriptCore 中重建
Raycast 扩展所需的 React、`@raycast/api`、Node/Web API 和 Swift host bridge，把扩展的 React
界面转成 JSON，再由 GearMac 的 Swift 原生 UI 显示。
