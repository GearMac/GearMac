// 文件职责：为 Raycast 扩展包提供 Node 内置模块（path/os/fs/process/child_process/crypto/zlib/http 等）的 shim 实现，把文件、进程、加密等能力转发给宿主 Swift 侧的同步或异步 host call。
// 分层：RaycastRuntime 运行时层；扩展包保持 external 的 Node 内置模块全部由此解析，文件/进程/加密类操作是同步 host call（由 Swift 在 JS 线程上服务），流/套接字类模块可以解析但一使用即抛错，因此仅引用它们的扩展包仍能加载。

import { hostCall, hostCallSync } from "./host.js";
import { Buffer, bufferModule } from "./buffer.js";
import { EventEmitter } from "./events.js";
import { base64ToBytes, bytesToBase64, reportUncaught, utf8Decode, utf8Encode } from "./polyfills.js";
import {
  Duplex,
  PassThrough,
  Readable,
  Stream,
  Transform,
  Writable,
  finished,
  finishedPromise,
  pipeline,
  pipelinePromise,
} from "./streams.js";
import { ReadableStream, TransformStream, WritableStream } from "./web-streams.js";
import { fileURLToPath, pathToFileURL, URL, URLSearchParams } from "./url.js";
import { punycode } from "./punycode.js";
import { upgradeToWebSocket } from "./websocket.js";
import { dgram } from "./dgram.js";

// ─── 不受支持的模块导出 ─────────────────────────────────────

/// Node 各模块的函数导出名单：惰性成员只有作为自有键（own key）才能在 `__toESM` 转换后保留下来。
const UNSUPPORTED_EXPORTS = {
  net: ["BlockList", "SocketAddress", "connect", "createConnection", "createServer", "isIP", "isIPv4", "isIPv6", "Server", "Socket", "Stream"],
  tls: ["getCiphers", "checkServerIdentity", "convertALPNProtocols", "createSecureContext", "SecureContext", "TLSSocket", "Server", "createServer", "connect"],
  dns: ["lookup", "lookupService", "Resolver", "getServers", "setServers", "getDefaultResultOrder", "setDefaultResultOrder", "resolve", "resolve4", "resolve6", "resolveAny", "resolveCaa", "resolveCname", "resolveMx", "resolveNaptr", "resolveNs", "resolvePtr", "resolveSoa", "resolveSrv", "resolveTlsa", "resolveTxt", "reverse"],
  vm: ["Script", "createContext", "createScript", "runInContext", "runInNewContext", "runInThisContext", "isContext", "compileFunction", "measureMemory"],
  readline: ["Interface", "clearLine", "clearScreenDown", "createInterface", "cursorTo", "emitKeypressEvents", "moveCursor"],
  worker_threads: ["MessagePort", "MessageChannel", "markAsUncloneable", "markAsUntransferable", "isMarkedAsUntransferable", "moveMessagePortToContext", "receiveMessageOnPort", "postMessageToThread", "Worker", "BroadcastChannel", "setEnvironmentData", "getEnvironmentData"],
  http2: ["connect", "createServer", "createSecureServer", "getDefaultSettings", "getPackedSettings", "getUnpackedSettings", "performServerHandshake", "Http2ServerRequest", "Http2ServerResponse"],
  domain: ["Domain", "createDomain", "create"],
  diagnostics_channel: ["channel", "hasSubscribers", "subscribe", "unsubscribe", "tracingChannel", "Channel"],
  "stream/consumers": ["arrayBuffer", "blob", "buffer", "text", "json"],
};

// ─── path（路径处理） ───────────────────────────────────────────────────────────

/// 按 POSIX 规则折叠路径分段：去掉空段与 `.`，处理 `..`（allowAboveRoot 为真时允许越过根目录保留 `..`）。
function normalizeSegments(parts, allowAboveRoot) {
  const out = [];
  for (const part of parts) {
    if (!part || part === ".") continue;
    if (part === "..") {
      if (out.length && out[out.length - 1] !== "..") out.pop();
      else if (allowAboveRoot) out.push("..");
    } else {
      out.push(part);
    }
  }
  return out;
}

/// Node `path` 模块的 POSIX 实现（`posix` 与 `win32` 均指向同一对象）。
const path = {
  sep: "/",
  delimiter: ":",
  normalize(input) {
    const text = String(input);
    if (!text) return ".";
    const absolute = text.startsWith("/");
    const trailing = text.endsWith("/");
    let joined = normalizeSegments(text.split("/"), !absolute).join("/");
    if (!joined && !absolute) joined = ".";
    if (joined && trailing) joined += "/";
    return absolute ? "/" + joined : joined;
  },
  join(...parts) {
    const joined = parts.filter((part) => part !== undefined && part !== null && part !== "").join("/");
    return joined ? path.normalize(joined) : ".";
  },
  resolve(...parts) {
    let resolved = "";
    for (let i = parts.length - 1; i >= 0; i--) {
      const part = parts[i];
      if (!part) continue;
      resolved = resolved ? `${part}/${resolved}` : String(part);
      if (String(part).startsWith("/")) break;
    }
    if (!resolved.startsWith("/")) resolved = `${process.cwd()}/${resolved}`;
    const normalized = "/" + normalizeSegments(resolved.split("/"), false).join("/");
    return normalized === "/" ? "/" : normalized.replace(/\/$/, "");
  },
  isAbsolute(input) {
    return String(input).startsWith("/");
  },
  dirname(input) {
    const text = String(input).replace(/\/+$/, "");
    const index = text.lastIndexOf("/");
    if (index < 0) return ".";
    if (index === 0) return "/";
    return text.slice(0, index);
  },
  basename(input, ext) {
    const text = String(input).replace(/\/+$/, "");
    let base = text.slice(text.lastIndexOf("/") + 1);
    if (ext && base.endsWith(ext) && base !== ext) base = base.slice(0, -ext.length);
    return base;
  },
  extname(input) {
    const base = path.basename(input);
    const dot = base.lastIndexOf(".");
    return dot <= 0 ? "" : base.slice(dot);
  },
  relative(from, to) {
    const fromParts = path.resolve(from).split("/").filter(Boolean);
    const toParts = path.resolve(to).split("/").filter(Boolean);
    let shared = 0;
    while (shared < fromParts.length && shared < toParts.length && fromParts[shared] === toParts[shared]) {
      shared++;
    }
    return [...Array(fromParts.length - shared).fill(".."), ...toParts.slice(shared)].join("/");
  },
  parse(input) {
    const dir = path.dirname(input);
    const base = path.basename(input);
    const ext = path.extname(base);
    return { root: String(input).startsWith("/") ? "/" : "", dir, base, ext, name: base.slice(0, base.length - ext.length) };
  },
  format(parsed) {
    const dir = parsed.dir || parsed.root || "";
    const base = parsed.base || `${parsed.name || ""}${parsed.ext || ""}`;
    return dir ? (dir === "/" ? "/" + base : `${dir}/${base}`) : base;
  },
  toNamespacedPath: (input) => input,
};
path.posix = path;
path.win32 = path;

// ─── process（进程） ────────────────────────────────────────────────────────

/// 宿主在启动时注入的环境信息（平台、架构、env、cwd、homedir 等）。
let bootEnvironment = { platform: "darwin", arch: "arm64", env: {}, cwd: "/", homedir: "/", tmpdir: "/tmp", execPath: "" };

/// 用宿主注入的信息覆盖启动环境，并同步到 process 的 env / arch / execPath。
export function configureNodeShims(info) {
  bootEnvironment = { ...bootEnvironment, ...info };
  process.env = bootEnvironment.env;
  process.arch = bootEnvironment.arch;
  process.execPath = bootEnvironment.execPath;
}

/// 按事件名保存的 process 监听器集合。
const processListeners = new Map();

/// 信号名到编号的映射（与 Node 保持一致）。
const SIGNALS = {
  SIGHUP: 1, SIGINT: 2, SIGQUIT: 3, SIGILL: 4, SIGTRAP: 5, SIGABRT: 6, SIGIOT: 6, SIGFPE: 8, SIGKILL: 9,
  SIGBUS: 10, SIGSEGV: 11, SIGSYS: 12, SIGPIPE: 13, SIGALRM: 14, SIGTERM: 15, SIGURG: 16, SIGSTOP: 17,
  SIGTSTP: 18, SIGCONT: 19, SIGCHLD: 20, SIGTTIN: 21, SIGTTOU: 22, SIGIO: 23, SIGXCPU: 24, SIGXFSZ: 25,
  SIGVTALRM: 26, SIGPROF: 27, SIGWINCH: 28, SIGINFO: 29, SIGUSR1: 30, SIGUSR2: 31,
};

/// 把信号名或编号统一转成编号；未知信号抛出带 ERR_UNKNOWN_SIGNAL 的 TypeError。
function signalNumber(signal) {
  if (typeof signal === "number") return signal;
  if (Object.hasOwn(SIGNALS, signal)) return SIGNALS[signal];
  const error = new TypeError(`Unknown signal: ${signal}`);
  error.code = "ERR_UNKNOWN_SIGNAL";
  throw error;
}

/// 简化版全局 `process` 对象：只暴露扩展包常用的字段与事件 API。
const process = {
  // axios 依据该 tag 决定是否启用 Node http 适配器；没有该 tag 时 axios 会走 fetch 分支。
  [Symbol.toStringTag]: "process",
  platform: "darwin",
  arch: "arm64",
  version: "v22.0.0",
  versions: { node: "22.0.0", v8: "12.0.0", gearmac: "1" },
  argv: ["node", "extension"],
  argv0: "node",
  execArgv: [],
  execPath: "",
  pid: 1,
  ppid: 0,
  env: {},
  title: "gearmac-extension",
  stdout: { write: (text) => console.log(String(text).replace(/\n$/, "")), isTTY: false, columns: 80 },
  stderr: { write: (text) => console.error(String(text).replace(/\n$/, "")), isTTY: false, columns: 80 },
  stdin: { on: () => {}, resume: () => {}, pause: () => {}, isTTY: false },
  cwd: () => bootEnvironment.cwd,
  chdir: () => {
    throw new Error("process.chdir is not supported in GearMac extensions.");
  },
  exit: () => {
    throw new Error("process.exit is not supported in GearMac extensions.");
  },
  kill(pid, signal = "SIGTERM") {
    hostCallSync("proc", "kill", [Number(pid), signalNumber(signal)]);
    return true;
  },
  nextTick: (callback, ...args) => {
    queueMicrotask(() => {
      try {
        callback(...args);
      } catch (error) {
        reportUncaught(error);
      }
    });
  },
  hrtime: Object.assign(
    (previous) => {
      const now = Date.now() * 1e6;
      const seconds = Math.floor(now / 1e9);
      const nanos = now % 1e9;
      if (!previous) return [seconds, nanos];
      return [seconds - previous[0], nanos - previous[1]];
    },
    { bigint: () => BigInt(Math.round(Date.now() * 1e6)) },
  ),
  uptime: () => Date.now() / 1000,
  memoryUsage: () => ({ rss: 0, heapTotal: 0, heapUsed: 0, external: 0, arrayBuffers: 0 }),
  emitWarning: (warning) => console.warn(String(warning)),
  on(event, listener) {
    if (!processListeners.has(event)) processListeners.set(event, new Set());
    processListeners.get(event).add(listener);
    return process;
  },
  once(event, listener) {
    return process.on(event, listener);
  },
  addListener(event, listener) {
    return process.on(event, listener);
  },
  off(event, listener) {
    processListeners.get(event)?.delete(listener);
    return process;
  },
  removeListener(event, listener) {
    return process.off(event, listener);
  },
  removeAllListeners(event) {
    if (event) processListeners.delete(event);
    else processListeners.clear();
    return process;
  },
  listeners: (event) => Array.from(processListeners.get(event) ?? []),
  emit(event, ...args) {
    const listeners = processListeners.get(event);
    if (!listeners?.size) return false;
    for (const listener of listeners) {
      try {
        listener(...args);
      } catch (error) {
        reportUncaught(error);
      }
    }
    return true;
  },
};

// ─── os（操作系统信息） ─────────────────────────────────────────────────────────────

/// 简化版 `os` 模块：平台信息取自宿主注入的启动环境，资源用量类方法走同步 host call。
const os = {
  EOL: "\n",
  platform: () => "darwin",
  type: () => "Darwin",
  arch: () => bootEnvironment.arch,
  release: () => bootEnvironment.release || "",
  homedir: () => bootEnvironment.homedir,
  tmpdir: () => bootEnvironment.tmpdir,
  hostname: () => bootEnvironment.hostname || "localhost",
  userInfo: () => ({
    username: bootEnvironment.username || "",
    homedir: bootEnvironment.homedir,
    shell: bootEnvironment.shell || "/bin/zsh",
    uid: 501,
    gid: 20,
  }),
  cpus: () => hostCallSync("os", "cpus", []),
  totalmem: () => bootEnvironment.totalmem || 0,
  freemem: () => hostCallSync("os", "freemem", []),
  uptime: () => hostCallSync("os", "uptime", []),
  loadavg: () => hostCallSync("os", "loadavg", []),
  networkInterfaces: () => ({}),
  endianness: () => "LE",
  devNull: "/dev/null",
  constants: { signals: SIGNALS, errno: {} },
};

// ─── fs（文件系统） ─────────────────────────────────────────────────────────────

/// 把宿主返回的 base64 内容按 options 指定的编码解码为字符串；未指定编码时返回 Buffer。
function decodeFileResult(result, options) {
  const encoding = typeof options === "string" ? options : options?.encoding;
  const bytes = base64ToBytes(result);
  return encoding ? Buffer.from(bytes).toString(encoding) : Buffer.from(bytes);
}

/// 把待写入数据编码为 base64；字符串按 options 的 encoding（默认 utf8）处理。
function encodeFileData(data, options) {
  if (typeof data === "string") {
    const encoding = typeof options === "string" ? options : options?.encoding;
    return bytesToBase64(Buffer.from(data, encoding || "utf8"));
  }
  if (data instanceof Uint8Array) return bytesToBase64(data);
  if (data instanceof ArrayBuffer) return bytesToBase64(new Uint8Array(data));
  return bytesToBase64(utf8Encode(String(data)));
}

/// `fs.Stats` 的简化实现：把宿主返回的原始字段包装为带日期对象与类型判定的对象。
class Stats {
  constructor(raw) {
    Object.assign(this, raw);
    this.atime = new Date(raw.atimeMs || 0);
    this.mtime = new Date(raw.mtimeMs || 0);
    this.ctime = new Date(raw.ctimeMs || 0);
    this.birthtime = new Date(raw.birthtimeMs || 0);
  }
  isFile() {
    return !!this._isFile;
  }
  isDirectory() {
    return !!this._isDirectory;
  }
  isSymbolicLink() {
    return !!this._isSymbolicLink;
  }
  isBlockDevice() {
    return false;
  }
  isCharacterDevice() {
    return false;
  }
  isFIFO() {
    return false;
  }
  isSocket() {
    return false;
  }
}

/// `fs.Dirent` 的简化实现：记录目录项名称与文件类型标记。
class Dirent {
  constructor(raw) {
    this.name = raw.name;
    this.parentPath = raw.parentPath;
    this.path = raw.parentPath;
    this._isFile = raw._isFile;
    this._isDirectory = raw._isDirectory;
    this._isSymbolicLink = raw._isSymbolicLink;
  }
  isFile() {
    return !!this._isFile;
  }
  isDirectory() {
    return !!this._isDirectory;
  }
  isSymbolicLink() {
    return !!this._isSymbolicLink;
  }
}

function fsPath(input) {
  // Node 会先经 fileURLToPath 校验 URL 入参：非 file 协议（例如 VS Code 的 vscode-remote:// 工作区 URI）
  // 必须抛 ERR_INVALID_URL_SCHEME，而不能默默退化成它的 pathname——Search Recent Projects 这类扩展
  // 正是靠这个失败来判定的。
  if (input instanceof URL) return fileURLToPath(input);
  if (input instanceof Uint8Array) return utf8Decode(input);
  return String(input);
}

// Node 的 mode 既可以是数字也可以是八进制字符串，而 Raycast 的 Swift 包装层传的是 "755"。
function fsMode(mode) {
  const parsed = typeof mode === "string" ? Number.parseInt(mode, 8) : Math.trunc(Number(mode));
  if (!Number.isFinite(parsed)) throw new TypeError(`Invalid file mode: ${mode}`);
  return parsed & 0o7777;
}

/// 文件流每次向宿主读取的默认块大小。
const FILE_STREAM_CHUNK = 64 * 1024;
/// `fs.constants` 的取值：访问权限位与 open flag 常量。
const FS_CONSTANTS = { F_OK: 0, R_OK: 4, W_OK: 2, X_OK: 1, O_RDONLY: 0, O_WRONLY: 1, O_RDWR: 2, O_APPEND: 8, O_NOFOLLOW: 256, O_CREAT: 512, O_TRUNC: 1024, O_EXCL: 2048 };
const { O_RDONLY, O_WRONLY, O_RDWR, O_APPEND, O_CREAT, O_TRUNC, O_EXCL } = FS_CONSTANTS;
/// `fs.openSync` 的字符串 flag 到数值 flag 的映射。
const OPEN_FLAGS = {
  r: O_RDONLY, "r+": O_RDWR,
  w: O_WRONLY | O_CREAT | O_TRUNC, "w+": O_RDWR | O_CREAT | O_TRUNC,
  wx: O_WRONLY | O_CREAT | O_TRUNC | O_EXCL, "wx+": O_RDWR | O_CREAT | O_TRUNC | O_EXCL,
  a: O_WRONLY | O_CREAT | O_APPEND, "a+": O_RDWR | O_CREAT | O_APPEND,
  ax: O_WRONLY | O_CREAT | O_APPEND | O_EXCL, "ax+": O_RDWR | O_CREAT | O_APPEND | O_EXCL,
};

/// 同步版 `fs` 模块：所有文件操作都通过 hostCallSync 交给宿主执行；回调与 Promise 形式由此派生。
const fs = {
  constants: FS_CONSTANTS,

  openSync(file, flags = "r", mode = 0o666) {
    const value = typeof flags === "number" ? flags : OPEN_FLAGS[flags];
    if (value === undefined) throw new TypeError(`Invalid file flags: ${flags}`);
    return hostCallSync("fs", "open", [fsPath(file), value, fsMode(mode)]);
  },
  closeSync(fd) {
    hostCallSync("fs", "close", [fd]);
  },
  readSync(fd, buffer, offset = 0, length = buffer.length - offset, position = null) {
    if (offset < 0 || length < 0 || offset + length > buffer.length) throw new RangeError("Read exceeds buffer bounds");
    const bytes = base64ToBytes(hostCallSync("fs", "read", [fd, length, position]));
    buffer.set(bytes, offset);
    return bytes.length;
  },
  writeSync(fd, buffer, offset = 0, length = buffer.length - offset, position = null) {
    if (offset < 0 || length < 0 || offset + length > buffer.length) throw new RangeError("Write exceeds buffer bounds");
    return hostCallSync("fs", "write", [fd, bytesToBase64(buffer.subarray(offset, offset + length)), position]);
  },
  readFileSync(file, options) {
    return decodeFileResult(hostCallSync("fs", "readFile", [fsPath(file)]), options);
  },
  writeFileSync(file, data, options) {
    hostCallSync("fs", "writeFile", [fsPath(file), encodeFileData(data, options), false]);
  },
  appendFileSync(file, data, options) {
    hostCallSync("fs", "writeFile", [fsPath(file), encodeFileData(data, options), true]);
  },
  existsSync(file) {
    try {
      return hostCallSync("fs", "exists", [fsPath(file)]);
    } catch {
      return false;
    }
  },
  statSync(file, options) {
    try {
      return new Stats(hostCallSync("fs", "stat", [fsPath(file), false]));
    } catch (error) {
      if (options?.throwIfNoEntry === false) return undefined;
      throw error;
    }
  },
  lstatSync(file, options) {
    try {
      return new Stats(hostCallSync("fs", "stat", [fsPath(file), true]));
    } catch (error) {
      if (options?.throwIfNoEntry === false) return undefined;
      throw error;
    }
  },
  readdirSync(dir, options) {
    const entries = hostCallSync("fs", "readdir", [fsPath(dir)]);
    if (options?.withFileTypes) return entries.map((entry) => new Dirent(entry));
    return entries.map((entry) => entry.name);
  },
  mkdirSync(dir, options) {
    return hostCallSync("fs", "mkdir", [fsPath(dir), !!(options === true || options?.recursive)]);
  },
  rmSync(target, options) {
    hostCallSync("fs", "remove", [fsPath(target), !!options?.recursive, !!options?.force]);
  },
  rmdirSync(target, options) {
    hostCallSync("fs", "remove", [fsPath(target), !!options?.recursive, false]);
  },
  unlinkSync(target) {
    hostCallSync("fs", "remove", [fsPath(target), false, false]);
  },
  renameSync(from, to) {
    hostCallSync("fs", "rename", [fsPath(from), fsPath(to)]);
  },
  copyFileSync(from, to) {
    hostCallSync("fs", "copyFile", [fsPath(from), fsPath(to)]);
  },
  realpathSync(target) {
    return hostCallSync("fs", "realpath", [fsPath(target)]);
  },
  accessSync(target) {
    if (!fs.existsSync(target)) {
      const error = new Error(`ENOENT: no such file or directory, access '${fsPath(target)}'`);
      error.code = "ENOENT";
      throw error;
    }
  },
  mkdtempSync(prefix) {
    return hostCallSync("fs", "mkdtemp", [String(prefix)]);
  },
  chmodSync(file, mode) {
    hostCallSync("fs", "chmod", [fsPath(file), fsMode(mode)]);
  },
  utimesSync(file, atime, mtime) {
    const times = [atime, mtime].map((time) => {
      const seconds = time instanceof Date ? time.getTime() / 1000 : Number(time);
      if (!Number.isFinite(seconds)) {
        throw Object.assign(new TypeError("Invalid file timestamp"), { code: "ERR_INVALID_ARG_VALUE" });
      }
      return typeof time === "number" && seconds < 0 ? Date.now() / 1000 : seconds;
    });
    hostCallSync("fs", "utimes", [fsPath(file), ...times]);
  },
  futimesSync() {},
  watch() {
    throw new Error("fs.watch is not supported in GearMac extensions.");
  },
  createReadStream(file, options) {
    const target = fsPath(file);
    const encoding = typeof options === "string" ? options : options?.encoding;
    const span = options?.highWaterMark ?? FILE_STREAM_CHUNK;
    let offset = options?.start ?? 0;
    const stream = new Readable({
      highWaterMark: span,
      read() {
        try {
          const bytes = base64ToBytes(hostCallSync("fs", "readRange", [target, offset, span]));
          offset += bytes.length;
          this.push(bytes.length ? Buffer.from(bytes) : null);
        } catch (error) {
          this.destroy(error);
        }
      },
    });
    stream.path = target;
    if (encoding) stream.setEncoding(encoding);
    return stream;
  },
  // 宿主没有文件句柄，所以每次写入都是独立调用：先创建一次，之后改为追加。
  createWriteStream(file, options) {
    const target = fsPath(file);
    let append = options?.flags === "a" || options?.flags === "a+";
    const put = (data) => {
      hostCallSync("fs", "writeFile", [target, bytesToBase64(data), append]);
      append = true;
    };
    const stream = new Writable({
      write(chunk, encoding, callback) {
        const data = typeof chunk === "string" ? Buffer.from(chunk, encoding) : chunk;
        try {
          put(data);
        } catch (error) {
          return callback(error);
        }
        stream.bytesWritten += data.length;
        callback(null);
      },
      final(callback) {
        try {
          if (!append) put(new Uint8Array(0));
        } catch (error) {
          return callback(error);
        }
        callback(null);
      },
    });
    stream.bytesWritten = 0;
    stream.path = target;
    return stream;
  },
  opendirSync(dir) {
    return new Dir(fsPath(dir), fs.readdirSync(dir, { withFileTypes: true }));
  },
  Stats,
  Dirent,
};

// 宿主没有目录句柄，所以 Dir 遍历的是打开时拍下的一份快照。
class Dir {
  #entries;
  #closed = false;
  constructor(path, entries) {
    this.path = path;
    this.#entries = entries;
  }
  #assertOpen() {
    if (!this.#closed) return;
    const error = new Error("Directory handle was closed");
    error.code = "ERR_DIR_CLOSED";
    throw error;
  }
  readSync() {
    this.#assertOpen();
    return this.#entries.shift() ?? null;
  }
  read(callback) {
    if (!callback) return (async () => this.readSync())();
    callbackify(() => this.readSync())(callback);
  }
  closeSync() {
    this.#assertOpen();
    this.#closed = true;
  }
  close(callback) {
    if (!callback) return (async () => this.closeSync())();
    callbackify(() => this.closeSync())(callback);
  }
  async *[Symbol.asyncIterator]() {
    try {
      for (let entry = this.readSync(); entry; entry = this.readSync()) yield entry;
    } finally {
      if (!this.#closed) this.closeSync();
    }
  }
}
fs.Dir = Dir;

// 回调形式：跑同一个同步 host call，把结果在 microtask 上回传。
function callbackify(syncFn) {
  return (...args) => {
    const callback = typeof args[args.length - 1] === "function" ? args.pop() : null;
    let value;
    let error = null;
    try {
      value = syncFn(...args);
    } catch (thrown) {
      error = thrown;
    }
    if (!callback) return;
    queueMicrotask(() => callback(error, error ? undefined : value));
  };
}

for (const [name, sync] of [
  ["open", fs.openSync],
  ["close", fs.closeSync],
  ["futimes", fs.futimesSync],
  ["utimes", fs.utimesSync],
  ["readFile", fs.readFileSync],
  ["writeFile", fs.writeFileSync],
  ["appendFile", fs.appendFileSync],
  ["stat", fs.statSync],
  ["lstat", fs.lstatSync],
  ["readdir", fs.readdirSync],
  ["opendir", fs.opendirSync],
  ["mkdir", fs.mkdirSync],
  ["rm", fs.rmSync],
  ["rmdir", fs.rmdirSync],
  ["unlink", fs.unlinkSync],
  ["rename", fs.renameSync],
  ["copyFile", fs.copyFileSync],
  ["realpath", fs.realpathSync],
  ["access", fs.accessSync],
  ["mkdtemp", fs.mkdtempSync],
  ["chmod", fs.chmodSync],
]) {
  fs[name] = callbackify(sync);
}
for (const name of ["read", "write"]) {
  fs[name] = (fd, buffer, offset, length, position, callback) => {
    callbackify(fs[`${name}Sync`])(fd, buffer, offset, length, position,
      (error, count) => callback(error, count, buffer));
  };
}
fs.exists = (file, callback) => queueMicrotask(() => callback(fs.existsSync(file)));

/// 把同步函数包装成返回 Promise 的异步函数。
function promisify1(syncFn) {
  return async (...args) => syncFn(...args);
}

/// `fs/promises` 的实现：直接复用对应的同步版本。
const fsPromises = {
  readFile: promisify1(fs.readFileSync),
  writeFile: promisify1(fs.writeFileSync),
  appendFile: promisify1(fs.appendFileSync),
  stat: promisify1(fs.statSync),
  lstat: promisify1(fs.lstatSync),
  readdir: promisify1(fs.readdirSync),
  opendir: promisify1(fs.opendirSync),
  mkdir: promisify1(fs.mkdirSync),
  rm: promisify1(fs.rmSync),
  rmdir: promisify1(fs.rmdirSync),
  unlink: promisify1(fs.unlinkSync),
  rename: promisify1(fs.renameSync),
  copyFile: promisify1(fs.copyFileSync),
  realpath: promisify1(fs.realpathSync),
  access: promisify1(fs.accessSync),
  mkdtemp: promisify1(fs.mkdtempSync),
  chmod: promisify1(fs.chmodSync),
  utimes: promisify1(fs.utimesSync),
  constants: fs.constants,
};
fs.promises = fsPromises;

// ─── child_process（子进程） ──────────────────────────────────────────────────

/// Node 会把每个已定义的值转成字符串，因此 `{ ...process.env, DEBUG: 1 }` 不能丢掉这个覆盖项。
function childEnv(env) {
  if (env == null) return env;
  return Object.fromEntries(Object.entries(env).filter(([, value]) => value !== undefined).map(([key, value]) => [key, String(value)]));
}

/// 归一化宿主返回的命令执行结果；encoding 为 buffer 或 null 时保留二进制。
function normalizeExecResult(raw, options) {
  const wantsBuffer = options?.encoding === "buffer" || options?.encoding === null;
  const decode = (base64) => (wantsBuffer ? Buffer.from(base64ToBytes(base64)) : utf8Decode(base64ToBytes(base64)));
  return { stdout: decode(raw.stdout), stderr: decode(raw.stderr), status: raw.status, signal: raw.signal ?? null };
}

/// 依据执行结果构造 Node 风格的 Error（带 code/status/stdout/stderr 字段）。
function execError(result, command) {
  const error = new Error(
    `Command failed: ${command}\n${typeof result.stderr === "string" ? result.stderr : ""}`.trim(),
  );
  error.code = result.status;
  error.status = result.status;
  error.stdout = result.stdout;
  error.stderr = result.stderr;
  error.killed = false;
  return error;
}

/// `child_process` 模块：exec/execFile/spawn 等均经宿主 proc host call 执行，不启动真实 Node 子进程。
const childProcess = {
  execSync(command, options = {}) {
    const raw = hostCallSync("proc", "run", [
      { shell: true, command: String(command), args: [], cwd: options.cwd, env: childEnv(options.env), timeout: options.timeout, input: options.input ? bytesToBase64(Buffer.from(options.input)) : null },
    ]);
    const result = normalizeExecResult(raw, options);
    if (result.status !== 0) throw execError(result, command);
    return result.stdout;
  },
  execFileSync(file, args = [], options = {}) {
    if (!Array.isArray(args)) {
      options = args;
      args = [];
    }
    const raw = hostCallSync("proc", "run", [
      { shell: false, command: String(file), args: args.map(String), cwd: options.cwd, env: childEnv(options.env), timeout: options.timeout, input: options.input ? bytesToBase64(Buffer.from(options.input)) : null },
    ]);
    const result = normalizeExecResult(raw, options);
    if (result.status !== 0) throw execError(result, file);
    return result.stdout;
  },
  spawnSync(file, args = [], options = {}) {
    if (!Array.isArray(args)) {
      options = args;
      args = [];
    }
    const raw = hostCallSync("proc", "run", [
      { shell: !!options.shell, command: String(file), args: args.map(String), cwd: options.cwd, env: childEnv(options.env), timeout: options.timeout, input: options.input ? bytesToBase64(Buffer.from(options.input)) : null },
    ]);
    const result = normalizeExecResult(raw, options);
    return { ...result, pid: 0, output: [null, result.stdout, result.stderr], error: undefined };
  },
  exec(command, options, callback) {
    if (typeof options === "function") {
      callback = options;
      options = {};
    }
    return runAsync({ shell: true, command: String(command), args: [], ...pickRunOptions(options) }, options, callback, command);
  },
  execFile(file, args, options, callback) {
    if (typeof args === "function") {
      callback = args;
      args = [];
      options = {};
    } else if (typeof options === "function") {
      callback = options;
      options = {};
    }
    if (!Array.isArray(args)) args = [];
    return runAsync(
      { shell: false, command: String(file), args: args.map(String), ...pickRunOptions(options) },
      options,
      callback,
      file,
    );
  },
  spawn(file, args = [], options = {}) {
    if (!Array.isArray(args)) {
      options = args;
      args = [];
    }
    return new ChildProcess(String(file), args.map(String), options);
  },
  fork() {
    throw new Error("child_process.fork is not supported in GearMac extensions.");
  },
};

// ─── crypto（加密） ─────────────────────────────────────────────────────────

/// 把字符串 / TypedArray / Buffer / ArrayBuffer 统一转成 Buffer。
function cryptoBytes(value, encoding) {
  if (typeof value === "string") return Buffer.from(value, encoding || "utf8");
  if (ArrayBuffer.isView(value)) return Buffer.from(new Uint8Array(value.buffer, value.byteOffset, value.byteLength));
  return Buffer.from(value);
}

/// 构造带 code 的加密相关错误。
function cryptoError(message, code, ErrorType = Error) {
  const error = new ErrorType(message);
  error.code = code;
  return error;
}

/// 哈希 / HMAC 实现：先累积数据，在 digest 时交给宿主 crypto.hash 或 crypto.hmac 计算。
class Hash {
  constructor(algorithm, hmacKeyBase64) {
    this._algorithm = String(algorithm).toLowerCase().replace(/-/g, "");
    this._key = hmacKeyBase64;
    this._chunks = [];
  }
  update(data, encoding) {
    this._chunks.push(cryptoBytes(data, encoding));
    return this;
  }
  digest(encoding) {
    const base64 = hostCallSync("crypto", this._key ? "hmac" : "hash", [
      this._algorithm,
      bytesToBase64(Buffer.concat(this._chunks)),
      this._key ?? null,
    ]);
    const bytes = Buffer.from(base64ToBytes(base64));
    return encoding ? bytes.toString(encoding) : bytes;
  }
}

// AES-CBC/ECB 加解密实现：update 先缓冲数据，final 时一次性交给宿主 crypto.cipher 处理，
// 这样分组密码的拼接输出与 Node 仍逐字节一致。
class Cipher {
  constructor(algorithm, key, iv, decrypt) {
    const name = String(algorithm).toLowerCase().replace(/^aes(128|192|256)$/, "aes-$1-cbc");
    const match = /^aes-(128|192|256)-(cbc|ecb)$/.exec(name);
    if (!match) throw cryptoError("Unknown cipher", "ERR_CRYPTO_UNKNOWN_CIPHER");
    this._mode = match[2];
    this._key = cryptoBytes(key);
    this._iv = iv == null ? Buffer.alloc(0) : cryptoBytes(iv);
    if (this._key.length !== Number(match[1]) / 8) {
      throw cryptoError("Invalid key length", "ERR_CRYPTO_INVALID_KEYLEN", RangeError);
    }
    if (this._iv.length !== (this._mode === "cbc" ? 16 : 0)) {
      throw cryptoError("Invalid initialization vector", "ERR_CRYPTO_INVALID_IV", TypeError);
    }
    this._decrypt = decrypt;
    this._padding = true;
    this._chunks = [];
    this._finished = false;
  }
  update(data, inputEncoding, outputEncoding) {
    if (this._finished) throw new Error("Trying to add data in unsupported state");
    this._chunks.push(cryptoBytes(data, inputEncoding));
    return outputEncoding ? "" : Buffer.alloc(0);
  }
  final(outputEncoding) {
    if (this._finished) throw cryptoError("Invalid state", "ERR_CRYPTO_INVALID_STATE");
    this._finished = true;
    const base64 = hostCallSync("crypto", "cipher", [
      this._mode,
      this._decrypt,
      bytesToBase64(this._key),
      bytesToBase64(this._iv),
      bytesToBase64(Buffer.concat(this._chunks)),
      this._padding,
    ]);
    const bytes = Buffer.from(base64ToBytes(base64));
    return outputEncoding ? bytes.toString(outputEncoding) : bytes;
  }
  setAutoPadding(enabled = true) {
    if (this._finished) throw cryptoError("Invalid state", "ERR_CRYPTO_INVALID_STATE");
    this._padding = Boolean(enabled);
    return this;
  }
}

/// 同步 PBKDF2 派生密钥，交由宿主 crypto.pbkdf2 计算。
function pbkdf2Sync(password, salt, iterations, keylen, digest) {
  const base64 = hostCallSync("crypto", "pbkdf2", [
    String(digest),
    bytesToBase64(cryptoBytes(password)),
    bytesToBase64(cryptoBytes(salt)),
    Number(iterations),
    Number(keylen),
  ]);
  return Buffer.from(base64ToBytes(base64));
}

/// 简化版 `crypto` 模块：随机数与加解密均转发给宿主，避免在 JS 侧实现底层算法。
const cryptoModule = {
  randomUUID: () => hostCallSync("crypto", "uuid", []),
  randomBytes(size, callback) {
    const bytes = Buffer.from(base64ToBytes(hostCallSync("crypto", "random", [size | 0])));
    if (callback) {
      queueMicrotask(() => callback(null, bytes));
      return;
    }
    return bytes;
  },
  randomFillSync(target) {
    const bytes = base64ToBytes(hostCallSync("crypto", "random", [target.length]));
    target.set(bytes.subarray(0, target.length));
    return target;
  },
  randomInt(min, max) {
    if (max === undefined) {
      max = min;
      min = 0;
    }
    const bytes = base64ToBytes(hostCallSync("crypto", "random", [4]));
    const value = ((bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3]) >>> 0;
    return min + (value % (max - min));
  },
  createHash: (algorithm) => new Hash(algorithm),
  createHmac: (algorithm, key) => new Hash(algorithm, bytesToBase64(cryptoBytes(key))),
  createCipheriv: (algorithm, key, iv) => new Cipher(algorithm, key, iv, false),
  createDecipheriv: (algorithm, key, iv) => new Cipher(algorithm, key, iv, true),
  pbkdf2Sync,
  pbkdf2(password, salt, iterations, keylen, digest, callback) {
    if (typeof callback !== "function") {
      throw cryptoError('The "callback" argument must be of type function.', "ERR_INVALID_ARG_TYPE", TypeError);
    }
    const key = pbkdf2Sync(password, salt, iterations, keylen, digest);
    queueMicrotask(() => callback(null, key));
  },
  timingSafeEqual: (a, b) => Buffer.from(a).equals(Buffer.from(b)),
  getHashes: () => ["md5", "sha1", "sha256", "sha384", "sha512"],
  getRandomValues: (target) => cryptoModule.randomFillSync(target),
  webcrypto: null,
  constants: {},
};
cryptoModule.webcrypto = { randomUUID: cryptoModule.randomUUID, getRandomValues: cryptoModule.getRandomValues, subtle: undefined };
if (!globalThis.crypto) globalThis.crypto = cryptoModule.webcrypto;

// ─── zlib（压缩） ───────────────────────────────────────────────────────────

/// 生成调用宿主 zlib 指定方法的同步压缩/解压函数。
function zlibSync(method) {
  return (data) => Buffer.from(base64ToBytes(hostCallSync("zlib", method, [bytesToBase64(Buffer.from(data))])));
}

// minizlib 会在 `_processChunk` 周围把 `Buffer.concat` 换成空实现，所以先把真正的那个存起来。
const concatBuffers = Buffer.concat;

/// `zlib.Unzip` 的最小实现：先缓冲数据，收到 flush 时按 gzip/inflate 自动识别并解压。
class Unzip extends EventEmitter {
  constructor() {
    super();
    this._chunks = [];
    this._handle = { close() {} };
  }
  _processChunk(chunk, flush) {
    this._chunks.push(Buffer.from(chunk));
    if (flush !== 4) return Buffer.alloc(0);
    const input = concatBuffers(this._chunks);
    this._chunks = [];
    if (!input.length) return input;
    return zlibSync(input[0] === 0x1f && input[1] === 0x8b ? "gunzip" : "inflate")(input);
  }
  close() {
    this._chunks = [];
    this._handle = null;
  }
}

/// zlib 模块的实现骨架：同步压缩函数，以及由它们派生的回调与流形式。
const zlibImpl = {
  Unzip,
  gzipSync: zlibSync("gzip"),
  gunzipSync: zlibSync("gunzip"),
  deflateSync: zlibSync("deflate"),
  inflateSync: zlibSync("inflate"),
  deflateRawSync: zlibSync("deflateRaw"),
  inflateRawSync: zlibSync("inflateRaw"),
  brotliCompressSync: () => {
    throw new Error("zlib brotli is not supported in GearMac extensions.");
  },
  brotliDecompressSync: () => {
    throw new Error("zlib brotli is not supported in GearMac extensions.");
  },
  constants: {},
};
for (const name of ["gzip", "gunzip", "deflate", "inflate", "deflateRaw", "inflateRaw"]) {
  const sync = zlibImpl[`${name}Sync`];
  zlibImpl[name] = callbackify(sync);
  zlibImpl[`create${name[0].toUpperCase()}${name.slice(1)}`] = () => {
    const chunks = [];
    return new Transform({
      transform(chunk, _enc, cb) {
        chunks.push(Buffer.from(chunk));
        cb();
      },
      flush(cb) {
        try {
          cb(null, sync(concatBuffers(chunks)));
        } catch (error) {
          cb(error);
        }
      },
    });
  };
}
const zlib = unsupportedModule("zlib", zlibImpl);

// ─── events（事件与子进程对象） ─────────────────────────────────────────────────────────

/// `child_process.spawn` 返回的对象：转发 stdout/stderr、收集 stdin，并通过宿主 proc host call 管理子进程生命周期。
class ChildProcess extends EventEmitter {
  constructor(file, args, options) {
    super();
    this.pid = 0;
    this.killed = false;
    this.exitCode = null;
    this.stdout = new PassThrough();
    this.stderr = new PassThrough();
    this._input = [];
    this._started = false;

    const self = this;
    this.stdin = new EventEmitter();
    this.stdin.writable = true;
    this.stdin.write = (chunk) => (self._input.push(typeof chunk === "string" ? Buffer.from(chunk, "utf8") : Buffer.from(chunk)), true);
    this.stdin.end = (chunk) => { if (chunk !== undefined) this.stdin.write(chunk); self._start(file, args, options); return this.stdin; };
    this.stdin.destroy = () => {};
    this.stdio = [this.stdin, this.stdout, this.stderr];

    // 用 microtask 而不是定时器启动。调用方会在 `spawn()` 之后同步写 stdin
    // （`p.stdin.write(q); p.stdin.end()`），microtask 仍能收集到；但与定时器不同，
    // 它能保证在控制权交回 Swift 之前排空。若用定时器，no-view 命令里
    // `spawn(...).unref()` 这类即发即弃调用可能在命令结束、上下文被销毁时仍处于
    // 待处理状态，子进程就永远不会启动。
    queueMicrotask(() => this._start(file, args, options));
  }

  _start(file, args, options) {
    if (this._started) return;
    this._started = true;
    const input = this._input.length ? bytesToBase64(Buffer.concat(this._input)) : null;
    const { pid, exit } = startChild({
      shell: !!options.shell,
      command: file,
      args,
      cwd: options.cwd,
      env: childEnv(options.env),
      timeout: options.timeout,
      input,
      // `detached` 只用来建立进程组；只有不去读输出的子进程才可能在退出前就返回。
      detached: !!options.detached && (Array.isArray(options.stdio) ? options.stdio[1] : options.stdio) === "ignore",
    }, (pid) => Promise.all([pipeChild(pid, 1, this.stdout), pipeChild(pid, 2, this.stderr)]));
    this.pid = pid;
    if (pid) queueMicrotask(() => this.emit("spawn"));
    exit.then(
      (raw) => {
        this.exitCode = raw.status;
        this.stdin.emit("finish");
        this.stdout.end(Buffer.from(base64ToBytes(raw.stdout)));
        this.stderr.end(Buffer.from(base64ToBytes(raw.stderr)));
        // 宿主的一次回复同时携带两者，但读取方仍期望先拿到输出、再收到退出码。
        queueMicrotask(() => {
          this.emit("exit", raw.status, raw.signal ?? null);
          this.emit("close", raw.status, raw.signal ?? null);
        });
      },
      (error) => {
        // 失败时也要关闭各个流：否则等 stdout 的消费者（execa 就是）会拿到
        // `undefined`，而 Node 保证那里是空字符串。
        this.exitCode = 1;
        this.stdin.emit("finish");
        this.stdout.end();
        this.stderr.end(Buffer.from(String(error?.message ?? error), "utf8"));
        this.emit("error", error);
        queueMicrotask(() => this.emit("close", 1, null));
      },
    );
  }

  kill(signal) {
    return this.exitCode === null && signalChild(this, signal);
  }

  // Node 用这两个方法把子进程从事件循环上解绑。这里没有任何东西会让运行时保持存活，
  // 所以它们只需存在并可链式调用——`spawn(...).unref()` 是很常见的写法。
  unref() {
    return this;
  }
  ref() {
    return this;
  }
}

// `util.promisify(exec)` 必须解析为 `{stdout, stderr}` 而不是单独的 stdout——扩展会解构这个结果，
// 而 Node 就是通过这个 symbol 声明该形状的。
const PROMISIFY_CUSTOM = Symbol.for("nodejs.util.promisify.custom");
childProcess.exec[PROMISIFY_CUSTOM] = (command, options) =>
  new Promise((resolve, reject) => {
    childProcess.exec(command, options, (error, stdout, stderr) => {
      if (error) {
        error.stdout = stdout;
        error.stderr = stderr;
        reject(error);
      } else {
        resolve({ stdout, stderr });
      }
    });
  });
childProcess.execFile[PROMISIFY_CUSTOM] = (file, args, options) =>
  new Promise((resolve, reject) => {
    childProcess.execFile(file, args, options, (error, stdout, stderr) => {
      if (error) {
        error.stdout = stdout;
        error.stderr = stderr;
        reject(error);
      } else {
        resolve({ stdout, stderr });
      }
    });
  });

/// 从调用参数中提取交给宿主的执行选项（cwd/env/timeout/input）。
function pickRunOptions(options = {}) {
  return { cwd: options.cwd, env: childEnv(options.env), timeout: options.timeout, input: options.input ? bytesToBase64(Buffer.from(options.input)) : null };
}

/// Node 保证失败的 exec 错误对象上带有 `stdout` / `stderr`，而扩展会检查它们（常见的做法是
/// `error.stderr.match(…)` 来区分“表不存在”与真正的失败）。直接拒绝的 host call 两者都没有，所以在这里补上。
function decorateProcessError(error, label) {
  const decorated = error instanceof Error ? error : new Error(String(error));
  if (decorated.stdout === undefined) decorated.stdout = "";
  if (decorated.stderr === undefined) decorated.stderr = decorated.message;
  if (decorated.status === undefined) decorated.status = 1;
  if (decorated.code === undefined) decorated.code = 1;
  decorated.cmd = decorated.cmd ?? label;
  return decorated;
}

/// 同步启动，因为扩展会立即把 `child.pid` 存下来，以便稍后向 process.kill 传入。
function startChild(spec, drain) {
  try {
    const pid = hostCallSync("proc", "start", [spec]);
    const exit = spec.detached
      ? Promise.resolve({ stdout: "", stderr: "", status: 0 })
      : Promise.resolve(drain?.(pid)).then(() => hostCall("proc", "wait", [pid]));
    return { pid, exit };
  } catch (error) {
    return { pid: undefined, exit: Promise.reject(error) };
  }
}

/// 持续从宿主的子进程 fd 读取输出并写入对应流，直到读取结束。
async function pipeChild(pid, fd, stream) {
  let held = Buffer.alloc(0);
  for (let chunk; (chunk = await hostCall("proc", "read", [pid, fd])); ) {
    const bytes = Buffer.concat([held, Buffer.from(base64ToBytes(chunk))]);
    const cut = utf8Boundary(bytes);
    held = bytes.subarray(cut);
    if (cut) stream.write(bytes.subarray(0, cut));
  }
  if (held.length) stream.write(held);
}

/// 截留末尾不完整的 UTF-8 字符，避免一个字符被分块拆断。
function utf8Boundary(bytes) {
  for (let i = bytes.length - 1; i >= Math.max(0, bytes.length - 3); i--) {
    if ((bytes[i] & 0xc0) === 0x80) continue;
    const need = bytes[i] >= 0xf0 ? 4 : bytes[i] >= 0xe0 ? 3 : bytes[i] >= 0xc0 ? 2 : 1;
    return bytes.length - i < need ? i : bytes.length;
  }
  return bytes.length;
}

/// Node 的 `ChildProcess.kill` 对于无法送达的信号只返回 false，从不抛错。
function signalChild(child, signal) {
  if (!child.pid) return false;
  try {
    process.kill(child.pid, signal);
  } catch {
    return false;
  }
  child.killed = true;
  return true;
}

/// 以回调 / Promise 形式异步执行命令，内部复用 startChild。
function runAsync(spec, options, callback, label) {
  const { pid, exit } = startChild(spec);
  let exited = false;
  const promise = exit
    .finally(() => {
      exited = true;
    })
    .then((raw) => normalizeExecResult(raw, options))
    .catch((error) => {
      throw decorateProcessError(error, label);
    });
  if (callback) {
    promise.then(
      (result) => callback(result.status === 0 ? null : execError(result, label), result.stdout, result.stderr),
      (error) => callback(error, error.stdout ?? "", error.stderr ?? ""),
    );
  }
  // Node 会返回 ChildProcess；扩展大多忽略它，或直接 await promisify 后的形式。
  const handle = { pid, killed: false, kill: (signal) => !exited && signalChild(handle, signal), on: () => handle, stdout: null, stderr: null };
  handle.then = promise.then.bind(promise);
  handle.catch = promise.catch.bind(promise);
  handle[Symbol.for("nodejs.util.promisify.custom")] = () => promise;
  return handle;
}

// ─── http / https（HTTP 客户端） ───────────────────────────────────────────────────

// 扩展包会自带 HTTP 客户端（node-fetch 就伴在 `@raycast/utils` 里），它们驱动 `http.request`
// 而不是全局 `fetch`。这里单个请求双向缓冲，走与 `fetch` 相同的 URLSession 桥：
// 没有 socket、没有流式传输、没有 keep-alive。
class IncomingMessage extends PassThrough {
  constructor(raw) {
    super();
    this.statusCode = raw.status ?? 200;
    this.statusMessage = raw.statusText ?? "";
    this.httpVersion = "1.1";
    this.url = raw.url ?? "";
    this.complete = true;
    // 桥自己会解码响应体，所以留着这些头会让客户端对明文再做一次 gunzip。
    this.headers = Object.fromEntries(
      Object.entries(raw.headers ?? {}).filter(
        ([name]) => name !== "content-encoding" && name !== "content-length",
      ),
    );
    // URLSession 会把重复的 `Set-Cookie` 头折叠成一行；而 Node 总是给出数组。
    if (typeof this.headers["set-cookie"] === "string") {
      this.headers["set-cookie"] = this.headers["set-cookie"].split(SET_COOKIE_BOUNDARY);
    }
    this.rawHeaders = Object.entries(this.headers).flatMap(([name, value]) =>
      [value].flat().flatMap((item) => [name, item]),
    );
  }
}

/// 一个开启下一个 `name=` 的逗号，而绝不会匹配 `Expires` 日期里的那个逗号。
const SET_COOKIE_BOUNDARY = /,\s*(?=[^;,=\s]+=)/;

/// 合法的 HTTP header 名称字符集。
const HEADER_TOKEN = /^[\^`\-\w!#$%&'*+.|~]+$/;
/// HTTP header 值中不允许出现的字符。
const HEADER_VALUE = /[^\t\u0020-\u007e\u0080-\u00ff]/;

/// 构造带 code 的 header 校验错误。
function headerError(message, code) {
  const error = new TypeError(message);
  error.code = code;
  return error;
}

/// 校验 header 名称，非法时抛 ERR_INVALID_HTTP_TOKEN。
function validateHeaderName(name) {
  if (typeof name !== "string" || !HEADER_TOKEN.test(name)) {
    throw headerError(`Header name must be a valid HTTP token ["${name}"]`, "ERR_INVALID_HTTP_TOKEN");
  }
}

/// 校验 header 值，非法时抛 ERR_HTTP_INVALID_HEADER_VALUE。
function validateHeaderValue(name, value) {
  if (value === undefined) {
    throw headerError(`Invalid value "undefined" for header "${name}"`, "ERR_HTTP_INVALID_HEADER_VALUE");
  }
  if (HEADER_VALUE.test(String(value))) {
    throw headerError(`Invalid character in header content ["${name}"]`, "ERR_INVALID_CHAR");
  }
}

/// 桥拥有所有 socket；`addRequest` 只是给 cookie agent 覆写的钩子。
class Agent extends EventEmitter {
  constructor(options) {
    super();
    this.options = { ...options };
  }

  addRequest() {}

  destroy() {}
}

/// `http.ClientRequest` 的实现：缓冲请求体后经宿主 fetch.request 发出，并把结果伪装成 IncomingMessage。
class ClientRequest extends EventEmitter {
  constructor(url, options, callback) {
    super();
    this.url = url;
    // 格式错误的 URL 仍然像以往那样失败：桥拒绝后触发一次 `error`。
    if (URL.canParse(url)) {
      const target = new URL(url);
      this.protocol = target.protocol;
      this.host = target.hostname;
      this.path = target.pathname + target.search;
    }
    this.method = String(options.method ?? "GET").toUpperCase();
    this.writable = true;
    this.writableEnded = false;
    this._headers = new Map();
    this._chunks = [];
    this._destroyed = false;
    for (const [name, value] of Object.entries(options.headers ?? {})) this.setHeader(name, value);
    if (callback) this.once("response", callback);
    // 换成别的 agent 形状（agent-base 6 extends EventEmitter）会去尝试打开 socket。
    if (options.agent instanceof Agent) options.agent.addRequest(this, options);
  }

  /// Node 在 header 发出前最后一次修改它们的机会；cookie agent 会包装它。
  _implicitHeader() {}

  setHeader(name, value) {
    this._headers.set(String(name).toLowerCase(), Array.isArray(value) ? value.join(", ") : String(value));
    return this;
  }

  getHeader(name) {
    return this._headers.get(String(name).toLowerCase());
  }

  getHeaders() {
    return Object.fromEntries(this._headers);
  }

  removeHeader(name) {
    this._headers.delete(String(name).toLowerCase());
  }

  write(chunk) {
    this._chunks.push(Buffer.from(chunk));
    return true;
  }

  end(chunk) {
    if (chunk !== undefined && chunk !== null) this.write(chunk);
    this._implicitHeader();
    this.writableEnded = true;
    this._send();
    return this;
  }

  abort() {
    return this.destroy();
  }

  destroy(error) {
    this._destroyed = true;
    clearTimeout(this._timer);
    if (error) this.emit("error", error);
    return this;
  }

  setTimeout(ms, callback) {
    if (callback) this.once("timeout", callback);
    clearTimeout(this._timer);
    this._timer = setTimeout(() => this.emit("timeout"), ms);
    return this;
  }

  setNoDelay() {
    return this;
  }

  setSocketKeepAlive() {
    return this;
  }

  flushHeaders() {}

  async _send() {
    if (String(this.getHeader("upgrade") ?? "").toLowerCase() === "websocket") return this._upgrade();
    // 内容协商属于传输层，它会替我们解码并报告结果。
    this.removeHeader("accept-encoding");
    const body = this._chunks.length ? Buffer.concat(this._chunks) : null;
    try {
      const raw = await hostCall("fetch", "request", [
        {
          url: this.url,
          method: this.method,
          headers: this.getHeaders(),
          bodyBase64: body === null ? null : body.toString("base64"),
        },
      ]);
      if (this._destroyed) return;
      clearTimeout(this._timer);
      const response = new IncomingMessage(raw);
      this.emit("response", response);
      response.end(Buffer.from(raw.bodyBase64 ?? "", "base64"));
      this.emit("close");
    } catch (error) {
      clearTimeout(this._timer);
      if (!this._destroyed) this.emit("error", error instanceof Error ? error : new Error(String(error)));
    }
  }

  /// 套接字由宿主打开，所以 101 响应是合成的——因为不会有扩展，所以也不做 deflate。
  async _upgrade() {
    const headers = this.getHeaders();
    try {
      const { socket, protocol } = await upgradeToWebSocket({
        url: this.url.replace(/^http/, "ws"),
        protocols: splitList(headers["sec-websocket-protocol"]),
        headers: Object.fromEntries(
          Object.entries(headers).filter(([name]) => !HANDSHAKE_HEADERS.has(name)),
        ),
      });
      clearTimeout(this._timer);
      if (this._destroyed) return socket.destroy();
      const accept = new Hash("sha1").update(`${headers["sec-websocket-key"] ?? ""}${WEBSOCKET_GUID}`).digest("base64");
      const response = new IncomingMessage({
        status: 101,
        statusText: "Switching Protocols",
        headers: {
          upgrade: "websocket",
          connection: "Upgrade",
          "sec-websocket-accept": accept,
          ...(protocol ? { "sec-websocket-protocol": protocol } : {}),
        },
      });
      if (!this.emit("upgrade", response, socket, Buffer.alloc(0))) socket.destroy();
    } catch (error) {
      clearTimeout(this._timer);
      if (!this._destroyed) this.emit("error", error instanceof Error ? error : new Error(String(error)));
    }
  }
}

/// WebSocket 握手约定的固定 GUID。
const WEBSOCKET_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

/// URLSession 自己写握手；转发这些头反而会让它拒绝请求。
const HANDSHAKE_HEADERS = new Set([
  "connection", "upgrade", "host", "sec-websocket-key", "sec-websocket-version",
  "sec-websocket-extensions", "sec-websocket-protocol",
]);

/// 把逗号分隔的 header 值拆成去空白的数组。
function splitList(value) {
  return String(value ?? "").split(",").map((item) => item.trim()).filter(Boolean);
}

/// http/https 的 request 实现：把各种入参形式归一为 ClientRequest。
function httpRequest(input, options, callback, scheme = "http:") {
  if (typeof options === "function") return httpRequest(input, {}, options, scheme);
  if (typeof input === "string" || input instanceof URL) {
    return new ClientRequest(String(input), options ?? {}, callback);
  }
  const spec = input ?? {};
  const host = spec.hostname ?? spec.host ?? "localhost";
  const port = spec.port ? `:${spec.port}` : "";
  return new ClientRequest(`${spec.protocol ?? scheme}//${host}${port}${spec.path ?? "/"}`, spec, callback);
}

/// http/https 的 get 实现：发出请求并立即 end。
function httpGet(input, options, callback, scheme) {
  return httpRequest(input, options, callback, scheme).end();
}

// ─── util（工具函数） ───────────────────────────────────────────────────────────

/// `util.inspect` 的极简实现，用于日志与调试输出。
function inspect(value, depth = 2) {
  if (typeof value === "string") return `'${value}'`;
  if (typeof value === "function") return `[Function: ${value.name || "anonymous"}]`;
  if (value instanceof Error) return value.stack || String(value);
  if (value === null || typeof value !== "object") return String(value);
  if (depth < 0) return Array.isArray(value) ? "[Array]" : "[Object]";
  if (Array.isArray(value)) return `[ ${value.map((item) => inspect(item, depth - 1)).join(", ")} ]`;
  const body = Object.keys(value)
    .map((key) => `${key}: ${inspect(value[key], depth - 1)}`)
    .join(", ");
  return `{ ${body} }`;
}

/// `util.format` 的实现，支持 %s/%d/%i/%f/%j/%o/%O/%% 占位符。
function format(first, ...rest) {
  if (typeof first !== "string") return [first, ...rest].map((value) => inspect(value)).join(" ");
  let index = 0;
  const text = first.replace(/%[sdifjoO%]/g, (token) => {
    if (token === "%%") return "%";
    if (index >= rest.length) return token;
    const value = rest[index++];
    switch (token) {
      case "%s":
        return typeof value === "string" ? value : inspect(value);
      case "%d":
      case "%i":
        return String(parseInt(value, 10));
      case "%f":
        return String(parseFloat(value));
      case "%j":
        return JSON.stringify(value);
      default:
        return inspect(value);
    }
  });
  return [text, ...rest.slice(index).map((value) => inspect(value))].join(" ");
}

/// 所有 TypedArray 构造器，用于生成 util.types 的判定函数。
const TYPED_ARRAYS = [Int8Array, Uint8Array, Uint8ClampedArray, Int16Array, Uint16Array, Int32Array, Uint32Array, Float32Array, Float64Array, BigInt64Array, BigUint64Array];
/// 装箱基础类型的内部 tag 名。
const BOXED_TAGS = ["Boolean", "Number", "String", "Symbol", "BigInt"];

/// 取对象的内部 tag（如 "Date"、"Arguments"）。
const tagOf = (value) => Object.prototype.toString.call(value).slice(8, -1);
/// 判断是否为装箱的基础类型对象（Boolean/Number/String/Symbol/BigInt）。
const isBoxed = (value) => typeof value === "object" && value !== null && BOXED_TAGS.includes(tagOf(value));

/// Node 完整的 `util.types` 表：如果某个成员缺失，只会返回 false 的判定函数会变成 TypeError——
/// 而 node-fetch 会对它归一化的每个请求体调用 `isBoxedPrimitive`。
const types = {
  isDate: (value) => value instanceof Date,
  isRegExp: (value) => value instanceof RegExp,
  isPromise: (value) => !!value && typeof value.then === "function",
  isMap: (value) => value instanceof Map,
  isSet: (value) => value instanceof Set,
  isWeakMap: (value) => value instanceof WeakMap,
  isWeakSet: (value) => value instanceof WeakSet,
  isNativeError: (value) => value instanceof Error,
  isArgumentsObject: (value) => tagOf(value) === "Arguments",
  isAsyncFunction: (value) => tagOf(value) === "AsyncFunction",
  isGeneratorFunction: (value) => tagOf(value) === "GeneratorFunction",
  isGeneratorObject: (value) => tagOf(value) === "Generator",
  isModuleNamespaceObject: (value) => tagOf(value) === "Module",
  isArrayBuffer: (value) => value instanceof ArrayBuffer,
  isSharedArrayBuffer: (value) => tagOf(value) === "SharedArrayBuffer",
  isAnyArrayBuffer: (value) => value instanceof ArrayBuffer || tagOf(value) === "SharedArrayBuffer",
  isArrayBufferView: (value) => ArrayBuffer.isView(value),
  isDataView: (value) => value instanceof DataView,
  isTypedArray: (value) => ArrayBuffer.isView(value) && !(value instanceof DataView),
  isBoxedPrimitive: isBoxed,
  isProxy: () => false,
  isExternal: () => false,
  isKeyObject: () => false,
  isCryptoKey: () => false,
  ...Object.fromEntries(TYPED_ARRAYS.map((Type) => [`is${Type.name}`, (value) => value instanceof Type])),
  ...Object.fromEntries(BOXED_TAGS.map((tag) => [`is${tag}Object`, (value) => isBoxed(value) && tagOf(value) === tag])),
};

/// Node 自带的 ANSI 匹配正则，原样照搬：更宽松的版本会把 execa 消息里的可打印文本吃掉。
const VT_CONTROL = /[\u001B\u009B][[\]()#;?]*(?:(?:(?:(?:;[-a-zA-Z\d\/#&.:=?%@~_]+)*|[a-zA-Z\d]+(?:;[-a-zA-Z\d\/#&.:=?%@~_]*)*)?\u0007)|(?:(?:\d{1,4}(?:;\d{0,4})*)?[\dA-PR-TZcf-nq-uy=><~]))/g;

/// 判断 NODE_DEBUG 中是否启用了某个 section（支持 `*` 通配）。
const sectionEnabled = (section) =>
  String(process.env.NODE_DEBUG || "")
    .split(/[\s,]+/)
    .filter(Boolean)
    .some((token) =>
      new RegExp(`^${token.replace(/[.+?^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*")}$`, "i").test(section),
    );

/// execa 与 undici 都会在模块作用域调用它；缺少 `debuglog` 会让扩展包在命令运行前就失败。
function debuglog(section, onLogger) {
  const enabled = sectionEnabled(section);
  const logger = enabled
    ? (...args) => process.stderr.write(`${String(section).toUpperCase()} ${process.pid}: ${format(...args)}\n`)
    : () => {};
  logger.enabled = enabled;
  onLogger?.(logger);
  return logger;
}

/// `util.promisify.custom` 使用的全局 symbol。
const promisifyCustom = Symbol.for("nodejs.util.promisify.custom");

/// 简化版 `util` 模块：promisify/callbackify/inspect/format/debuglog 与 util.types 等。
const util = {
  promisify(fn) {
    if (fn[promisifyCustom]) return fn[promisifyCustom];
    return (...args) =>
      new Promise((resolve, reject) => {
        fn(...args, (error, value) => (error ? reject(error) : resolve(value)));
      });
  },
  callbackify(fn) {
    return (...args) => {
      const callback = args.pop();
      fn(...args).then((value) => callback(null, value), callback);
    };
  },
  inspect,
  format,
  formatWithOptions: (_options, ...args) => format(...args),
  debuglog,
  debug: debuglog,
  stripVTControlCharacters: (text) => String(text).replace(VT_CONTROL, ""),
  aborted: (signal) =>
    new Promise((resolve) => {
      if (signal.aborted) resolve();
      else signal.addEventListener("abort", () => resolve(), { once: true });
    }),
  /// 故意比 Node 宽容：扩展包会在加载时对某些模块（GearMac 只做了存根）里的类调用它，
  /// 在那里抛错会让一个根本不会走到该代码路径的扩展直接挂掉。
  inherits(child, parent) {
    if (!child?.prototype || !parent?.prototype) return;
    Object.setPrototypeOf(child.prototype, parent.prototype);
    child.super_ = parent;
  },
  deprecate: (fn) => fn,
  isDeepStrictEqual: (a, b) => JSON.stringify(a) === JSON.stringify(b),
  TextEncoder: globalThis.TextEncoder,
  TextDecoder: globalThis.TextDecoder,
  types,
};
util.promisify.custom = promisifyCustom;
util.inspect.custom = Symbol.for("nodejs.util.inspect.custom");

// ─── querystring / assert / string_decoder（查询串、断言、字符串解码） ──────────────────────────

/// 基于 URLSearchParams 的 querystring 实现。
const querystring = {
  parse(text) {
    const out = {};
    for (const [key, value] of new URLSearchParams(String(text || "").replace(/^[?]/, ""))) {
      if (out[key] === undefined) out[key] = value;
      else if (Array.isArray(out[key])) out[key].push(value);
      else out[key] = [out[key], value];
    }
    return out;
  },
  stringify(object) {
    const params = new URLSearchParams();
    for (const key of Object.keys(object || {})) {
      const value = object[key];
      if (Array.isArray(value)) for (const item of value) params.append(key, item);
      else params.append(key, value);
    }
    return params.toString();
  },
  escape: encodeURIComponent,
  unescape: decodeURIComponent,
};

/// Node 遗留下来的 `url.format`，同时也能处理 http-cookie-agent 每个请求构建的那类 parts 对象。
function formatURL(value) {
  if (typeof value !== "object" || value === null || value instanceof URL) return String(value);
  const protocol = value.protocol ? value.protocol.replace(/:?$/, ":") : "";
  const slashes = value.slashes || /^(https?|ftp|gopher|file|wss?):$/.test(protocol) ? "//" : "";
  const auth = value.auth ? `${value.auth}@` : "";
  const host = value.host ?? (value.hostname ? value.hostname + (value.port ? `:${value.port}` : "") : "");
  const pathname = (value.pathname ?? "").replace(/[?#]/g, encodeURIComponent);
  const query = value.query && typeof value.query === "object" ? querystring.stringify(value.query) : "";
  const search = value.search ?? (query ? `?${query}` : "");
  return `${protocol}${slashes}${auth}${host}${pathname}${search}${value.hash ?? ""}`;
}

/// assert 的最小实现及其各变体（ok/equal/strictEqual/deepStrictEqual/fail/throws 等）。
function assert(value, message) {
  if (!value) throw new Error(message || "Assertion failed");
}
assert.ok = assert;
assert.equal = (a, b, message) => assert(a == b, message || `${a} != ${b}`);
assert.strictEqual = (a, b, message) => assert(a === b, message || `${a} !== ${b}`);
assert.notStrictEqual = (a, b, message) => assert(a !== b, message || `${a} === ${b}`);
assert.deepStrictEqual = (a, b, message) =>
  assert(JSON.stringify(a) === JSON.stringify(b), message || "not deeply equal");
assert.fail = (message) => assert(false, message);
assert.throws = (fn, message) => {
  try {
    fn();
  } catch {
    return;
  }
  assert(false, message || "Missing expected exception");
};

/// `string_decoder.StringDecoder` 的简化实现：直接把字节按指定编码解码。
class StringDecoder {
  constructor(encoding = "utf8") {
    this.encoding = encoding;
  }
  write(bytes) {
    return Buffer.from(bytes).toString(this.encoding);
  }
  end(bytes) {
    return bytes ? this.write(bytes) : "";
  }
}

// ─── 可解析但拒绝运行的模块 ─────────────────────────

/// 一个所有成员都是“构造或调用即抛错”的类的模块。扩展包经常在加载时写
/// `class Foo extends stream.Readable`，只在条件分支里才会走到真正的运行路径，
/// 因此成员必须是一个真实的构造器——未知成员也得存在，所以用了 Proxy。
function unsupportedModule(name, extras = {}) {
  const cache = new Map();
  const lazy = new Set((UNSUPPORTED_EXPORTS[name] ?? []).filter((each) => !(each in extras)));
  const manufacture = (member) => {
    if (!cache.has(member)) cache.set(member, makeUnsupported(`${name}.${member}`));
    return cache.get(member);
  };
  return new Proxy(extras, {
    get(target, member) {
      if (member in target) return target[member];
      // 互操作与探测用的键必须保持缺失：一个真值的 `__esModule` 会让 esbuild 的 `__toESM`
      // 跳过它本应做的 default 包装，而真值的 `then` 会让模块在 `await` 看来像个 thenable。
      if (typeof member !== "string" || RESERVED_MEMBERS.has(member)) return undefined;
      return manufacture(member);
    },
    // esbuild 的 `__toESM` 会快照自有键，从不通过 `get` 读取。
    ownKeys: (target) => [...new Set([...Reflect.ownKeys(target), ...lazy])],
    getOwnPropertyDescriptor(target, member) {
      const own = Reflect.getOwnPropertyDescriptor(target, member);
      if (own || !lazy.has(member)) return own;
      return { value: manufacture(member), writable: true, enumerable: true, configurable: true };
    },
  });
}

/// 必须保持原样（不得被 Proxy 伪造成假成员）的属性名集合。
const RESERVED_MEMBERS = new Set(["__esModule", "default", "then", "catch", "prototype", "constructor", "toJSON", "inspect", "valueOf", "toString", "length", "name"]);

/// 生成一个“被构造或被调用即抛错”的占位导出。
function makeUnsupported(label) {
  const reason = `${label} is not supported in GearMac extensions (no Node runtime). See docs/extensions.md.`;
  const Unsupported = class {
    constructor() {
      throw new Error(reason);
    }
  };
  // 也可以像普通函数那样调用——`stream.pipeline(...)`、`https.request(...)`。
  return new Proxy(Unsupported, {
    apply() {
      throw new Error(reason);
    },
  });
}

/// 为 http/https 生成可用的模块对象：请求转发给宿主，其余成员按不支持处理。
const httpLike = (name) =>
  unsupportedModule(name, {
    // 协议随模块一起确定：`ws` 与 axios 都会传入不带 protocol 的选项对象。
    request: (input, options, callback) => httpRequest(input, options, callback, `${name}:`),
    get: (input, options, callback) => httpGet(input, options, callback, `${name}:`),
    validateHeaderName,
    validateHeaderValue,
    IncomingMessage,
    ClientRequest,
    Agent,
    globalAgent: new Agent(),
    STATUS_CODES: {},
    METHODS: [],
  });

/// Node 的流是 ES5 函数：axios 内部的 follow-redirects 会在它的 `this` 上调用 `Writable`。
function es5Constructible(Class) {
  return new Proxy(Class, {
    apply: (target, self, args) =>
      void Object.defineProperties(self, Object.getOwnPropertyDescriptors(new target(...args))),
  });
}

/// 可被当普通函数调用的流类集合（每个类都经 es5Constructible 包装）。
const streamClasses = {
  Stream: es5Constructible(Stream),
  Readable: es5Constructible(Readable),
  Writable: es5Constructible(Writable),
  Duplex: es5Constructible(Duplex),
  Transform: es5Constructible(Transform),
  PassThrough: es5Constructible(PassThrough),
};

/// stream 模块：常用流类可用，其余成员按不支持处理。
const streamModule = unsupportedModule(
  "stream",
  Object.assign(streamClasses.Stream, {
    ...streamClasses,
    getDefaultHighWaterMark: (objectMode) => (objectMode ? 16 : 16 * 1024),
    pipeline,
    finished,
    promises: { pipeline: (...stages) => pipelinePromise(stages), finished: finishedPromise },
  }),
);

/// `stream/web` 导出的 Web Streams 实现。
const webStreamModule = { ReadableStream, WritableStream, TransformStream };

/// http2-wrapper 在导入时就会读 `new tls.TLSSocket(stream)._handle._parentWrap.constructor`。
const TLSSocket = class TLSSocket extends Duplex {
  _handle = { _parentWrap: { constructor: TLSSocket } };
};

/// 同步单上下文场景下的 AsyncLocalStorage 占位实现，仅保证调用不报错。
class AsyncLocalStorage {
  run(_store, fn) {
    return fn();
  }
  getStore() {
    return undefined;
  }
}

/// undici 在模块作用域继承它；这里只有一个同步上下文，所以作用域就是这次调用本身。
class AsyncResource {
  constructor(type) {
    this.type = type;
  }
  runInAsyncScope(fn, thisArg, ...args) {
    return Reflect.apply(fn, thisArg, args);
  }
  bind(fn, thisArg = this) {
    return fn.bind(thisArg);
  }
  emitDestroy() {
    return this;
  }
  asyncId() {
    return 0;
  }
  triggerAsyncId() {
    return 0;
  }
}

// ─── diagnostics_channel（诊断通道） ────────────────────────────────────────────

/// undici 会在模块作用域为每个插桩点开一个 channel，所以 `channel` 不能拒绝。
class Channel {
  constructor(name) {
    this.name = name;
    this._subscribers = [];
  }
  get hasSubscribers() {
    return this._subscribers.length > 0;
  }
  subscribe(onMessage) {
    this._subscribers.push(onMessage);
  }
  unsubscribe(onMessage) {
    const index = this._subscribers.indexOf(onMessage);
    if (index === -1) return false;
    this._subscribers.splice(index, 1);
    return true;
  }
  publish(message) {
    for (const onMessage of [...this._subscribers]) {
      try {
        onMessage(message, this.name);
      } catch (error) {
        reportUncaught(error);
      }
    }
  }
  bindStore() {}
  unbindStore() {
    return false;
  }
  runStores(message, fn, thisArg, ...args) {
    this.publish(message);
    return Reflect.apply(fn, thisArg, args);
  }
}

/// 按名称缓存已创建的 diagnostics channel。
const channels = new Map();

/// 获取或新建指定名称的 channel。
function channel(name) {
  if (!channels.has(name)) channels.set(name, new Channel(name));
  return channels.get(name);
}

/// diagnostics_channel 模块：channel / subscribe 等可用，其余成员按不支持处理。
const diagnosticsChannel = unsupportedModule("diagnostics_channel", {
  Channel,
  channel,
  hasSubscribers: (name) => channels.get(name)?.hasSubscribers ?? false,
  subscribe: (name, onMessage) => channel(name).subscribe(onMessage),
  unsubscribe: (name, onMessage) => channels.get(name)?.unsubscribe(onMessage) ?? false,
});

// ─── 模块注册表 ───────────────────────────────────────────────────────

/// 模块名到 shim 实现的映射，也是运行时模块解析的入口。
export const nodeModules = {
  path,
  os,
  fs,
  "fs/promises": fsPromises,
  child_process: childProcess,
  crypto: cryptoModule,
  zlib,
  events: EventEmitter,
  util,
  buffer: bufferModule,
  process,
  querystring,
  punycode,
  assert,
  string_decoder: { StringDecoder },
  // node-fetch 会把解析好的 URL 展开到请求选项里，并从中读取遗留下来的 `path`。
  url: { URL, URLSearchParams, fileURLToPath, pathToFileURL, parse: (text) => Object.assign(new URL(text), { path: new URL(text).pathname + new URL(text).search }), format: formatURL, resolve: (from, to) => new URL(to, from).href },
  timers: { setTimeout, clearTimeout, setInterval, clearInterval, setImmediate, clearImmediate },
  "timers/promises": { setTimeout: (ms, value) => new Promise((resolve) => setTimeout(() => resolve(value), ms)) },
  perf_hooks: { performance: globalThis.performance },
  http: httpLike("http"),
  https: httpLike("https"),
  dgram,
  net: unsupportedModule("net"),
  tls: unsupportedModule("tls", { TLSSocket }),
  dns: unsupportedModule("dns"),
  stream: streamModule,
  "stream/web": webStreamModule,
  "stream/promises": { pipeline: (...stages) => pipelinePromise(stages), finished: finishedPromise },
  // 用空实现而不是直接拒绝：undici 的 `markAsUncloneable || (() => {})` 永远不会回退。
  worker_threads: unsupportedModule("worker_threads", {
    isMainThread: true,
    markAsUncloneable: () => {},
    markAsUntransferable: () => {},
    isMarkedAsUntransferable: () => false,
  }),
  readline: unsupportedModule("readline"),
  tty: { isatty: () => false },
  vm: unsupportedModule("vm"),
  module: { createRequire: () => requireStub, builtinModules: [] },
  constants: {},
  cluster: { isPrimary: true, isMaster: true },
  inspector: {},
  v8: {},
  async_hooks: { AsyncLocalStorage, AsyncResource },
  diagnostics_channel: diagnosticsChannel,
};

/// createRequire 的占位实现：一旦被调用即抛错。
function requireStub(name) {
  throw new Error(`createRequire is not supported in GearMac extensions (tried to load "${name}").`);
}

// 其余所有 Node 内置模块都解析为“使用时才拒绝”的存根。扩展包会从依赖里引用整个长尾模块
// （http2、domain、repl 等），而这些依赖只在扩展永远走不到的路径上才会碰它们，
// 所以在 require 时抛错会让那些实际能正常工作的扩展失败。
const REMAINING_BUILTINS = [
  "assert/strict", "console", "dns/promises", "domain", "http2",
  "inspector/promises", "path/posix", "path/win32", "readline/promises", "repl",
  "stream/consumers", "sys", "trace_events", "util/types", "wasi", "sea", "sqlite", "test",
  "test/reporters",
];
for (const name of REMAINING_BUILTINS) {
  if (!nodeModules[name]) nodeModules[name] = unsupportedModule(name);
}
nodeModules["assert/strict"] = assert;
nodeModules["path/posix"] = path;
nodeModules["path/win32"] = path;
nodeModules["util/types"] = util.types;
nodeModules["dns/promises"] = nodeModules.dns;
nodeModules["readline/promises"] = nodeModules.readline;
nodeModules.console = globalThis.console;

// Node 内置模块加不加 `node:` 前缀都能寻址。
for (const name of Object.keys(nodeModules)) {
  nodeModules[`node:${name}`] = nodeModules[name];
}

/// 把 shim 挂到全局，供扩展包直接使用。
globalThis.process = process;
globalThis.Buffer = Buffer;
globalThis.global = globalThis;

/// 重新导出扩展包常用的几个全局符号。
export { Buffer, process, EventEmitter };
