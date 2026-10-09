// 文件职责：为 JavaScriptCore 补齐扩展 bundle（以及 React scheduler）依赖、但运行时未提供的 Web/Node 全局能力。
// 分层：运行时 polyfill（Raycast JS runtime）；仅在对应全局缺失时才安装，时钟与网络传输由 Swift 侧提供。

import { hostCall, hostRaw, log } from "./host.js";
import {
  ReadableStream,
  TransformStream,
  WritableStream,
  bytesOfReadableStream,
  readableStreamOfBytes,
} from "./web-streams.js";

const g = globalThis;

if (!g.console) g.console = {};
for (const level of ["log", "info", "warn", "error", "debug", "trace"]) {
  g.console[level] = (...args) => log(level === "debug" || level === "trace" ? "log" : level, args);
}
// 扩展偶尔会调用这些方法；这里让它们成为空操作，而不是抛出 TypeError。
for (const noop of ["group", "groupEnd", "table", "time", "timeEnd", "dir", "assert", "count"]) {
  if (!g.console[noop]) g.console[noop] = () => {};
}

if (!g.performance) g.performance = { now: () => Date.now() };
else if (!g.performance.now) g.performance.now = () => Date.now();

// ─── 定时器 ─────────────────────────────────────────────────────────
// 时钟由 Swift 掌管：它在自己的 runloop 上调度，并回调 JS 侧的 `fireTimer`。

let nextTimerId = 1;
const timers = new Map();

/// 注册一个定时器并把调度交给 Swift 侧，返回递增的数字 id。
function schedule(callback, delay, repeats, args) {
  if (typeof callback !== "function") return 0;
  const id = nextTimerId++;
  timers.set(id, { callback, args, repeats });
  hostRaw.startTimer(String(id), Math.max(0, Number(delay) || 0), repeats);
  return id;
}

/// 取消定时器：从本地表移除并通知 Swift 侧清除。
function unschedule(id) {
  const key = Number(id);
  if (!timers.has(key)) return;
  timers.delete(key);
  hostRaw.clearTimer(String(key));
}

/// Swift 定时器到期时的回调入口，执行一次或重复触发的回调。
export function fireTimer(id) {
  const key = Number(id);
  const timer = timers.get(key);
  if (!timer) return;
  if (!timer.repeats) timers.delete(key);
  try {
    timer.callback(...timer.args);
  } catch (error) {
    reportUncaught(error);
  }
}

g.setTimeout = (cb, delay, ...args) => schedule(cb, delay, false, args);
g.setInterval = (cb, delay, ...args) => schedule(cb, delay, true, args);
g.clearTimeout = unschedule;
g.clearInterval = unschedule;
// Node 的 immediate/tick API，被打包进来的依赖所使用。
g.setImmediate = (cb, ...args) => schedule(cb, 0, false, args);
g.clearImmediate = unschedule;

if (!g.queueMicrotask) {
  const resolved = Promise.resolve();
  g.queueMicrotask = (cb) => {
    resolved.then(cb).catch(reportUncaught);
  };
}

// ─── WebAssembly ────────────────────────────────────────────────────
// JSC 的 promise 形式依赖一个 JS 队列永远不会驱动的 runloop 才会 settle；因此这里用同步构造器而不等待。

if (g.WebAssembly) {
  const { Module, Instance } = g.WebAssembly;
  const compile = (bytes) => new Promise((resolve) => resolve(new Module(bytes)));
  const instantiate = (source, imports) =>
    new Promise((resolve) => {
      if (source instanceof Module) {
        resolve(new Instance(source, imports));
        return;
      }
      const module = new Module(source);
      resolve({ module, instance: new Instance(module, imports) });
    });
  const bytesOf = async (source) => new Uint8Array(await (await source).arrayBuffer());
  g.WebAssembly.compile = compile;
  g.WebAssembly.instantiate = instantiate;
  g.WebAssembly.compileStreaming = async (source) => compile(await bytesOf(source));
  g.WebAssembly.instantiateStreaming = async (source, imports) =>
    instantiate(await bytesOf(source), imports);
}

// ─── 错误上报 ────────────────────────────────────────────────

let uncaughtSink = (error) => log("error", ["Uncaught:", error]);

/// 设置未捕获异常的上报出口。
export function setUncaughtHandler(handler) {
  uncaughtSink = handler;
}

/// 把未捕获异常交给已注册的出口；出口自身抛错时降级为日志。
export function reportUncaught(error) {
  try {
    uncaughtSink(error);
  } catch {
    log("error", ["Uncaught (and the handler threw):", error]);
  }
}

// ─── fetch ──────────────────────────────────────────────────────────
// 底层由 Swift 侧的 URLSession 支撑。请求体以 base64 跨桥传输，保证二进制响应不损坏；
// text/JSON 走同一条路径。

/// Headers 的最小实现：键名大小写不敏感，append 时以逗号合并同名值。
class GearMacHeaders {
  constructor(init) {
    this._map = new Map();
    if (init instanceof GearMacHeaders) {
      for (const [key, value] of init._map) this._map.set(key, value);
    } else if (Array.isArray(init)) {
      for (const [key, value] of init) this.append(key, value);
    } else if (init && typeof init === "object") {
      for (const key of Object.keys(init)) this.append(key, init[key]);
    }
  }
  _key(name) {
    return String(name).toLowerCase();
  }
  append(name, value) {
    const key = this._key(name);
    const existing = this._map.get(key);
    this._map.set(key, existing === undefined ? String(value) : `${existing}, ${value}`);
  }
  set(name, value) {
    this._map.set(this._key(name), String(value));
  }
  get(name) {
    const value = this._map.get(this._key(name));
    return value === undefined ? null : value;
  }
  has(name) {
    return this._map.has(this._key(name));
  }
  delete(name) {
    this._map.delete(this._key(name));
  }
  forEach(fn, thisArg) {
    for (const [key, value] of this._map) fn.call(thisArg, value, key, this);
  }
  keys() {
    return this._map.keys();
  }
  values() {
    return this._map.values();
  }
  entries() {
    return this._map.entries();
  }
  [Symbol.iterator]() {
    return this._map.entries();
  }
  toJSON() {
    return Object.fromEntries(this._map);
  }
}

const EMPTY_BYTES = new Uint8Array(0);

/// Blob 实现：以 Uint8Array 持有字节，支持文本/字节/流/切片读取。
class GearMacBlob {
  constructor(parts = [], options = {}) {
    this._bytes = concatBytes((parts ?? []).map(blobPartToBytes));
    const type = String(options?.type ?? "");
    this._type = /^[\x20-\x7e]*$/.test(type) ? type.toLowerCase() : "";
  }
  get size() {
    return this._bytes.length;
  }
  get type() {
    return this._type;
  }
  async arrayBuffer() {
    return this._bytes.slice().buffer;
  }
  async bytes() {
    return this._bytes.slice();
  }
  async text() {
    return utf8Decode(this._bytes);
  }
  stream() {
    return readableStreamOfBytes(this._bytes);
  }
  slice(start = 0, end = this.size, contentType = "") {
    const from = normalizeBlobIndex(start, this.size);
    const to = normalizeBlobIndex(end, this.size);
    return new GearMacBlob([this._bytes.subarray(Math.min(from, to), to)], { type: contentType });
  }
}

/// 把单个 Blob 组成项转换为字节。
function blobPartToBytes(part) {
  if (part instanceof GearMacBlob) return part._bytes;
  if (typeof part === "string") return utf8Encode(part);
  if (part instanceof ArrayBuffer) return new Uint8Array(part);
  if (ArrayBuffer.isView(part)) return new Uint8Array(part.buffer, part.byteOffset, part.byteLength);
  return utf8Encode(String(part));
}

/// 把多个字节块拼接成一个 Uint8Array。
function concatBytes(chunks) {
  const bytes = new Uint8Array(chunks.reduce((total, chunk) => total + chunk.length, 0));
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  return bytes;
}

/// 按 Blob.slice 语义把索引规范到 [0, size]，支持负值与 Infinity。
function normalizeBlobIndex(value, size) {
  const index = Number(value);
  if (Number.isNaN(index)) return 0;
  if (index === Infinity) return size;
  if (index === -Infinity) return 0;
  return Math.min(Math.max(index < 0 ? size + Math.ceil(index) : Math.floor(index), 0), size);
}

/// File 实现：在 Blob 基础上附带 name 与 lastModified。
class GearMacFile extends GearMacBlob {
  constructor(parts = [], name = "", options = {}) {
    super(parts, options);
    this.name = String(name);
    this.lastModified = options?.lastModified ?? Date.now();
  }
}

/// FormData 实现：持有条目列表，并生成 header 与 body 共用的 multipart 边界。
class GearMacFormData {
  constructor() {
    this._entries = [];
    // header 与 body 必须使用同一个 boundary，因此它保存在实例上，而不是编码器里。
    this._boundary = `----GearMacFormBoundary${Math.random().toString(36).slice(2, 18)}`;
  }
  append(name, value, filename) {
    this._entries.push([String(name), formDataValue(value, filename)]);
  }
  set(name, value, filename) {
    const key = String(name);
    const at = this._entries.findIndex(([existing]) => existing === key);
    this._entries = this._entries.filter(([existing]) => existing !== key);
    this._entries.splice(at === -1 ? this._entries.length : at, 0, [key, formDataValue(value, filename)]);
  }
  get(name) {
    const hit = this._entries.find(([existing]) => existing === String(name));
    return hit === undefined ? null : hit[1];
  }
  getAll(name) {
    return this._entries.filter(([existing]) => existing === String(name)).map(([, value]) => value);
  }
  has(name) {
    return this._entries.some(([existing]) => existing === String(name));
  }
  delete(name) {
    this._entries = this._entries.filter(([existing]) => existing !== String(name));
  }
  forEach(fn, thisArg) {
    for (const [name, value] of this._entries) fn.call(thisArg, value, name, this);
  }
  keys() {
    return this._entries.map(([name]) => name)[Symbol.iterator]();
  }
  values() {
    return this._entries.map(([, value]) => value)[Symbol.iterator]();
  }
  entries() {
    return this._entries.map(([name, value]) => [name, value])[Symbol.iterator]();
  }
  [Symbol.iterator]() {
    return this.entries();
  }
}

// 按规范，Blob 条目会变成名为 "blob" 的 File，除非调用方传入了 filename。
function formDataValue(value, filename) {
  if (!(value instanceof GearMacBlob)) return String(value);
  if (value instanceof GearMacFile && filename === undefined) return value;
  return new GearMacFile([value], filename ?? "blob", { type: value.type });
}

/// 按 multipart/form-data 规则序列化 FormData。
function formDataToBytes(form) {
  const chunks = [];
  for (const [name, value] of form._entries) {
    const disposition =
      value instanceof GearMacBlob
        ? `; name="${escapeFormName(name)}"; filename="${escapeFormName(value.name)}"`
        : `; name="${escapeFormName(name)}"`;
    const type = value instanceof GearMacBlob ? `Content-Type: ${value.type || "application/octet-stream"}\r\n` : "";
    chunks.push(utf8Encode(`--${form._boundary}\r\nContent-Disposition: form-data${disposition}\r\n${type}\r\n`));
    chunks.push(value instanceof GearMacBlob ? value._bytes : utf8Encode(value));
    chunks.push(utf8Encode("\r\n"));
  }
  chunks.push(utf8Encode(`--${form._boundary}--\r\n`));
  return concatBytes(chunks);
}

/// 转义 multipart 字段名中的换行与引号。
function escapeFormName(value) {
  return String(value).replace(/\n/g, "%0A").replace(/\r/g, "%0D").replace(/"/g, "%22");
}

if (!g.Blob) g.Blob = GearMacBlob;
if (!g.File) g.File = GearMacFile;
if (!g.FormData) g.FormData = GearMacFormData;

/// Response 实现：既支持一次性的字节体，也支持流式体，并记录 bodyUsed 状态。
class GearMacResponse {
  // 按规范形态实现：axios 一类库会在模块作用域构造 Response 以探测平台能力。
  constructor(body = null, init = {}, url = "") {
    this.status = init.status ?? 200;
    this.statusText = init.statusText ?? "";
    this.headers = new GearMacHeaders(init.headers);
    this.url = url;
    this.ok = this.status >= 200 && this.status < 300;
    this.redirected = false;
    this.type = "basic";
    this._stream = body instanceof ReadableStream ? body : null;
    this._bytes = this._stream ? null : (bodyToBytes(body) ?? EMPTY_BYTES);
    this._hasBody = body !== null && body !== undefined;
    this.bodyUsed = false;
  }
  // 字节已全部就绪，因此这里的 "stream" 只是按读取块大小分发，足够应付依赖 `response.body`
  // 并做 pipe 的扩展，但并非渐进式。
  get body() {
    if (!this._hasBody) return null;
    if (!this._stream) this._stream = readableStreamOfBytes(this._bytes);
    return this._stream;
  }
  clone() {
    const { status, statusText, headers } = this;
    return new GearMacResponse(this._bytes ?? this._stream, { status, statusText, headers }, this.url);
  }
  async arrayBuffer() {
    this.bodyUsed = true;
    return (await this.bytes()).buffer;
  }
  // 返回副本：body 的生命周期长于本次读取，调用方修改它不应影响后续读取者。
  async bytes() {
    this.bodyUsed = true;
    if (this._bytes === null) this._bytes = await bytesOfReadableStream(this._stream);
    return this._bytes.slice();
  }
  async text() {
    this.bodyUsed = true;
    if (this._bytes === null) this._bytes = await bytesOfReadableStream(this._stream);
    return utf8Decode(this._bytes);
  }
  async json() {
    return JSON.parse(await this.text());
  }
  async blob() {
    return new GearMacBlob([await this.bytes()], { type: this.headers.get("content-type") ?? "" });
  }
}

/// Request 实现：规范化 method/headers/body，并在缺失时补上隐式 Content-Type。
class GearMacRequest {
  constructor(input, init = {}) {
    if (input instanceof GearMacRequest) {
      this.url = input.url;
      this.method = init.method || input.method;
      this.headers = new GearMacHeaders(init.headers || input.headers);
      this.body = init.body !== undefined ? init.body : input.body;
    } else {
      this.url = String(input);
      this.method = (init.method || "GET").toUpperCase();
      this.headers = new GearMacHeaders(init.headers);
      this.body = init.body;
    }
    const implied = bodyContentType(this.body);
    if (implied && !this.headers.has("content-type")) this.headers.set("content-type", implied);
    this.signal = init.signal;
  }
}

/// fetch 实现：把请求交给 Swift 侧 URLSession，并把 base64 响应体还原为 Response。
async function gearmacFetch(input, init = {}) {
  const request = input instanceof GearMacRequest ? input : new GearMacRequest(input, init);
  const signal = init.signal || request.signal;
  if (signal?.aborted) throw abortError();

  const raw = await hostCall("fetch", "request", [
    {
      url: request.url,
      method: request.method,
      headers: request.headers.toJSON(),
      bodyBase64: encodeBody(request.body),
    },
  ]);
  if (signal?.aborted) throw abortError();
  return new GearMacResponse(
    base64ToBytes(raw.bodyBase64 || ""),
    { status: raw.status, statusText: raw.statusText, headers: raw.headers },
    raw.url || "",
  );
}

// gaxios 对每个错误都做 `instanceof DOMException` 判断，缺少 DOMException 时非 2xx 响应会直接抛错。
/// DOMException 的最小替代，仅保留 name 字段以满足 instanceof 判断。
class GearMacDOMException extends Error {
  constructor(message = "", name = "Error") {
    super(String(message));
    this.name = String(name);
  }
}

if (!g.DOMException) g.DOMException = GearMacDOMException;

/// 构造 name 为 AbortError 的错误。
function abortError() {
  const error = new Error("The operation was aborted.");
  error.name = "AbortError";
  return error;
}

// `AbortSignal.timeout` 以 TimeoutError（而非 AbortError）中止，调用方会根据 name 分支处理。
/// 构造 name 为 TimeoutError 的错误，供 `AbortSignal.timeout` 使用。
function timeoutError() {
  const error = new Error("The operation timed out.");
  error.name = "TimeoutError";
  return error;
}

/// 把各种 body 取值统一转换成字节。
function bodyToBytes(body) {
  if (body === undefined || body === null) return null;
  if (typeof body === "string") return utf8Encode(body);
  if (body instanceof GearMacBlob) return body._bytes;
  if (body instanceof GearMacFormData) return formDataToBytes(body);
  if (body instanceof Uint8Array) return body;
  if (body instanceof ArrayBuffer) return new Uint8Array(body);
  if (ArrayBuffer.isView(body)) return new Uint8Array(body.buffer, body.byteOffset, body.byteLength);
  if (body instanceof URLSearchParams) return utf8Encode(body.toString());
  return utf8Encode(String(body));
}

// 符合 Fetch 规范：body 会隐含一个 Content-Type，OAuth token POST 依赖它而非显式设置。
/// 根据 body 类型推断隐式 Content-Type。
function bodyContentType(body) {
  if (typeof body === "string") return "text/plain;charset=UTF-8";
  if (body instanceof URLSearchParams) return "application/x-www-form-urlencoded;charset=UTF-8";
  if (body instanceof GearMacFormData) return `multipart/form-data; boundary=${body._boundary}`;
  if (body instanceof GearMacBlob) return body.type || null;
  return null;
}

/// 把 body 编码为 base64，供跨桥传输。
function encodeBody(body) {
  const bytes = bodyToBytes(body);
  return bytes === null ? null : bytesToBase64(bytes);
}

if (!g.ReadableStream) {
  g.ReadableStream = ReadableStream;
  g.WritableStream = WritableStream;
  g.TransformStream = TransformStream;
}

if (!g.fetch) {
  g.fetch = gearmacFetch;
  g.Headers = GearMacHeaders;
  g.Response = GearMacResponse;
  g.Request = GearMacRequest;
}

// ─── AbortController ────────────────────────────────────────────────

if (!g.AbortController) {
  // node-fetch 在发送前会按构造器名与 tag 对 signal 做 brand check。
  class AbortSignal {
    static name = "AbortSignal";
    constructor() {
      this.aborted = false;
      this.reason = undefined;
      this._listeners = new Set();
      this.onabort = null;
    }
    get [Symbol.toStringTag]() {
      return "AbortSignal";
    }
    addEventListener(type, listener) {
      if (type === "abort") this._listeners.add(listener);
    }
    removeEventListener(type, listener) {
      if (type === "abort") this._listeners.delete(listener);
    }
    throwIfAborted() {
      if (this.aborted) throw this.reason ?? abortError();
    }
    // 必须实现静态方法而不只是实例形态：缺少静态方法在类型层面仍显示为受支持，
    // 于是扩展调用 `AbortSignal.timeout` 时会得到 "is not a function"。
    static abort(reason) {
      const signal = new AbortSignal();
      signal._fire(reason);
      return signal;
    }
    static timeout(ms) {
      const signal = new AbortSignal();
      setTimeout(() => signal._fire(timeoutError()), ms);
      return signal;
    }
    static any(signals) {
      const merged = new AbortSignal();
      for (const source of signals) {
        if (source?.aborted) {
          merged._fire(source.reason);
          break;
        }
        source?.addEventListener("abort", () => merged._fire(source.reason));
      }
      return merged;
    }
    _fire(reason) {
      if (this.aborted) return;
      this.aborted = true;
      this.reason = reason ?? abortError();
      const event = { type: "abort", target: this };
      if (typeof this.onabort === "function") this.onabort(event);
      for (const listener of this._listeners) {
        try {
          listener(event);
        } catch (error) {
          reportUncaught(error);
        }
      }
    }
  }
  g.AbortSignal = AbortSignal;
  g.AbortController = class {
    constructor() {
      this.signal = new AbortSignal();
    }
    abort(reason) {
      this.signal._fire(reason);
    }
  };
}

// ─── Event / EventTarget / MessageChannel ───────────────────────────
// 与 TextEncoder 一样属于 WebCore API：undici 会在模块作用域继承 Event 与 EventTarget。

/// Event 的最小实现，支持 preventDefault 与停止传播标记。
class GearMacEvent {
  constructor(type, init = {}) {
    if (arguments.length === 0) throw new TypeError("Event constructor requires a type argument.");
    this.type = String(type);
    this.bubbles = !!init.bubbles;
    this.cancelable = !!init.cancelable;
    this.composed = !!init.composed;
    this.defaultPrevented = false;
    this.isTrusted = false;
    this.target = null;
    this.currentTarget = null;
    this.eventPhase = 0;
    this.timeStamp = Date.now();
    this._stopped = false;
  }
  preventDefault() {
    if (this.cancelable) this.defaultPrevented = true;
  }
  stopPropagation() {}
  stopImmediatePropagation() {
    this._stopped = true;
  }
}

// 用 WeakMap 而非实例字段：子类与 `Object.create` 出来的实例不会执行本构造器。
const eventListeners = new WeakMap();

function listenersOf(target, type) {
  let byType = eventListeners.get(target);
  if (!byType) eventListeners.set(target, (byType = new Map()));
  let list = byType.get(type);
  if (!list) byType.set(type, (list = []));
  return list;
}

/// EventTarget 实现：监听器存放在 WeakMap 中，支持 capture/once/signal。
class GearMacEventTarget {
  addEventListener(type, callback, options) {
    if (callback == null) return;
    const { capture = false, once = false, signal } = typeof options === "boolean" ? { capture: options } : (options ?? {});
    if (signal?.aborted) return;
    const list = listenersOf(this, String(type));
    if (list.some((each) => each.callback === callback && each.capture === !!capture)) return;
    list.push({ callback, capture: !!capture, once: !!once, removed: false });
    signal?.addEventListener("abort", () => this.removeEventListener(type, callback, { capture }));
  }
  removeEventListener(type, callback, options) {
    const capture = !!(typeof options === "boolean" ? options : options?.capture);
    const list = eventListeners.get(this)?.get(String(type));
    const index = list?.findIndex((each) => each.callback === callback && each.capture === capture) ?? -1;
    if (index === -1) return;
    list[index].removed = true;
    list.splice(index, 1);
  }
  dispatchEvent(event) {
    if (!(event instanceof GearMacEvent)) throw new TypeError("dispatchEvent requires an Event.");
    event.target = this;
    event.currentTarget = this;
    event.eventPhase = 2;
    for (const listener of [...(eventListeners.get(this)?.get(event.type) ?? [])]) {
      if (listener.removed) continue;
      if (listener.once) this.removeEventListener(event.type, listener.callback, { capture: listener.capture });
      try {
        if (typeof listener.callback === "function") listener.callback.call(this, event);
        else listener.callback.handleEvent?.(event);
      } catch (error) {
        reportUncaught(error);
      }
      if (event._stopped) break;
    }
    event.currentTarget = null;
    event.eventPhase = 0;
    return !event.defaultPrevented;
  }
}

/// MessageEvent：只携带 data 与空的 ports。
class GearMacMessageEvent extends GearMacEvent {
  constructor(data) {
    super("message");
    this.data = data;
    this.ports = [];
  }
}

// Node 的 port 在首个 "message" 监听器上就启动，而不像浏览器那样只认 `start()`。
/// MessagePort：在一对互连端口之间传递结构化克隆消息。
class GearMacMessagePort extends GearMacEventTarget {
  _peer = null;
  _queue = [];
  _started = false;
  _closed = false;
  _onmessage = null;
  postMessage(message) {
    if (!this._peer) return;
    this._peer._receive(g.structuredClone(message));
  }
  start() {
    if (this._started || this._closed) return;
    this._started = true;
    for (const data of this._queue.splice(0)) this._schedule(data);
  }
  close() {
    this._closed = true;
    if (this._peer) this._peer._peer = null;
    this._peer = null;
    this._queue = [];
  }
  addEventListener(type, callback, options) {
    super.addEventListener(type, callback, options);
    if (type === "message") this.start();
  }
  get onmessage() {
    return this._onmessage;
  }
  set onmessage(handler) {
    if (this._onmessage) this.removeEventListener("message", this._onmessage);
    this._onmessage = typeof handler === "function" ? handler : null;
    if (this._onmessage) this.addEventListener("message", this._onmessage);
  }
  _receive(data) {
    if (this._started) this._schedule(data);
    else this._queue.push(data);
  }
  _schedule(data) {
    setTimeout(() => {
      if (!this._closed) this.dispatchEvent(new GearMacMessageEvent(data));
    }, 0);
  }
}

/// MessageChannel：创建一对互连的 MessagePort。
class GearMacMessageChannel {
  constructor() {
    this.port1 = new GearMacMessagePort();
    this.port2 = new GearMacMessagePort();
    this.port1._peer = this.port2;
    this.port2._peer = this.port1;
  }
}

if (!g.EventTarget) {
  g.Event = GearMacEvent;
  g.EventTarget = GearMacEventTarget;
}
if (!g.MessageChannel) {
  g.MessagePort = GearMacMessagePort;
  g.MessageChannel = GearMacMessageChannel;
}

// ─── 文本编码 / base64 ─────────────────────────────────────────

/// 把字符串编码为 UTF-8 字节。
export function utf8Encode(text) {
  const out = [];
  for (let i = 0; i < text.length; i++) {
    let code = text.codePointAt(i);
    if (code > 0xffff) i++;
    if (code < 0x80) out.push(code);
    else if (code < 0x800) out.push(0xc0 | (code >> 6), 0x80 | (code & 0x3f));
    else if (code < 0x10000)
      out.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f));
    else
      out.push(
        0xf0 | (code >> 18),
        0x80 | ((code >> 12) & 0x3f),
        0x80 | ((code >> 6) & 0x3f),
        0x80 | (code & 0x3f),
      );
  }
  return new Uint8Array(out);
}

/// 把 UTF-8 字节解码为字符串。
export function utf8Decode(bytes) {
  let out = "";
  for (let i = 0; i < bytes.length; ) {
    const byte = bytes[i++];
    if (byte < 0x80) out += String.fromCharCode(byte);
    else if (byte < 0xe0) out += String.fromCharCode(((byte & 0x1f) << 6) | (bytes[i++] & 0x3f));
    else if (byte < 0xf0)
      out += String.fromCharCode(
        ((byte & 0x0f) << 12) | ((bytes[i++] & 0x3f) << 6) | (bytes[i++] & 0x3f),
      );
    else {
      const code =
        ((byte & 0x07) << 18) |
        ((bytes[i++] & 0x3f) << 12) |
        ((bytes[i++] & 0x3f) << 6) |
        (bytes[i++] & 0x3f);
      out += String.fromCodePoint(code);
    }
  }
  return out;
}

const B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

/// 把字节编码为 base64 字符串。
export function bytesToBase64(bytes) {
  let out = "";
  for (let i = 0; i < bytes.length; i += 3) {
    const a = bytes[i];
    const b = bytes[i + 1];
    const c = bytes[i + 2];
    out += B64[a >> 2];
    out += B64[((a & 3) << 4) | ((b ?? 0) >> 4)];
    out += b === undefined ? "=" : B64[((b & 15) << 2) | ((c ?? 0) >> 6)];
    out += c === undefined ? "=" : B64[c & 63];
  }
  return out;
}

/// 把 base64 字符串解码为字节，忽略其中的非 base64 字符。
export function base64ToBytes(text) {
  const clean = String(text).replace(/[^A-Za-z0-9+/]/g, "");
  const out = new Uint8Array((clean.length * 3) >> 2);
  let outIndex = 0;
  for (let i = 0; i < clean.length; i += 4) {
    const a = B64.indexOf(clean[i]);
    const b = B64.indexOf(clean[i + 1]);
    const c = B64.indexOf(clean[i + 2]);
    const d = B64.indexOf(clean[i + 3]);
    out[outIndex++] = (a << 2) | (b >> 4);
    if (c >= 0) out[outIndex++] = ((b & 15) << 4) | (c >> 2);
    if (d >= 0) out[outIndex++] = ((c & 3) << 6) | d;
  }
  return out.subarray(0, outIndex);
}

if (!g.atob) g.atob = (text) => String.fromCharCode(...base64ToBytes(text));
if (!g.btoa) {
  g.btoa = (text) => {
    const bytes = new Uint8Array(text.length);
    for (let i = 0; i < text.length; i++) bytes[i] = text.charCodeAt(i) & 0xff;
    return bytesToBase64(bytes);
  };
}

if (!g.structuredClone) {
  g.structuredClone = (value) => (value === undefined ? undefined : JSON.parse(JSON.stringify(value)));
}

// JavaScriptCore 没有 TextEncoder/TextDecoder（它们属于 WebCore API），而打包依赖会随意使用。
// 这里只有 UTF-8 路径是真实的；请求其他编码时仍按 UTF-8 解码。
if (!g.TextEncoder) {
  g.TextEncoder = class TextEncoder {
    get encoding() {
      return "utf-8";
    }
    encode(text = "") {
      return utf8Encode(String(text));
    }
    encodeInto(text, target) {
      const bytes = utf8Encode(String(text));
      const written = Math.min(bytes.length, target.length);
      target.set(bytes.subarray(0, written));
      return { read: text.length, written };
    }
  };
}

if (!g.TextDecoder) {
  g.TextDecoder = class TextDecoder {
    constructor(encoding = "utf-8", options = {}) {
      this.encoding = String(encoding).toLowerCase();
      this.fatal = !!options.fatal;
      this.ignoreBOM = !!options.ignoreBOM;
    }
    decode(input) {
      if (input === undefined) return "";
      let bytes;
      if (input instanceof Uint8Array) bytes = input;
      else if (input instanceof ArrayBuffer) bytes = new Uint8Array(input);
      else if (ArrayBuffer.isView(input))
        bytes = new Uint8Array(input.buffer, input.byteOffset, input.byteLength);
      else throw new TypeError("TextDecoder.decode: unsupported input");
      if (!this.ignoreBOM && bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf) {
        bytes = bytes.subarray(3);
      }
      return utf8Decode(bytes);
    }
  };
}
