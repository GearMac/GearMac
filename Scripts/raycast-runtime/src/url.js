// 文件职责：为不提供它们的 JavaScriptCore 实现 URL 与 URLSearchParams，覆盖扩展会构造与解析的层级式 http(s) 风格 URL。
// 分层：运行时模块（Raycast JS runtime）；只求覆盖扩展实际用法，并非完整 WHATWG 实现（不做 IDNA，也不对 host 做百分号编码规范化）。

const SPECIAL_PORTS = { "http:": "80", "https:": "443", "ws:": "80", "wss:": "443", "ftp:": "21" };

/// URL 查询参数实现：以有序键值对存储，写操作会同步回宿主 URL 的 search。
export class URLSearchParams {
  constructor(init) {
    this._pairs = [];
    this._owner = null;
    if (init === undefined || init === null) return;
    if (init instanceof URLSearchParams) {
      this._pairs = init._pairs.map((pair) => [pair[0], pair[1]]);
    } else if (typeof init === "string") {
      this._parse(init);
    } else if (Array.isArray(init)) {
      for (const pair of init) this._pairs.push([String(pair[0]), String(pair[1])]);
    } else if (typeof init[Symbol.iterator] === "function") {
      for (const pair of init) this._pairs.push([String(pair[0]), String(pair[1])]);
    } else if (typeof init === "object") {
      for (const key of Object.keys(init)) this._pairs.push([key, String(init[key])]);
    }
  }

  _parse(text) {
    const body = String(text).replace(/^[?]/, "");
    if (!body) return;
    for (const chunk of body.split("&")) {
      if (!chunk) continue;
      const eq = chunk.indexOf("=");
      const key = eq < 0 ? chunk : chunk.slice(0, eq);
      const value = eq < 0 ? "" : chunk.slice(eq + 1);
      this._pairs.push([decodeComponent(key), decodeComponent(value)]);
    }
  }

  _changed() {
    if (this._owner) this._owner._syncSearchFromParams();
  }

  append(key, value) {
    this._pairs.push([String(key), String(value)]);
    this._changed();
  }
  delete(key, value) {
    const name = String(key);
    this._pairs = this._pairs.filter(
      (pair) => pair[0] !== name || (value !== undefined && pair[1] !== String(value)),
    );
    this._changed();
  }
  get(key) {
    const hit = this._pairs.find((pair) => pair[0] === String(key));
    return hit ? hit[1] : null;
  }
  getAll(key) {
    return this._pairs.filter((pair) => pair[0] === String(key)).map((pair) => pair[1]);
  }
  has(key, value) {
    const name = String(key);
    return this._pairs.some(
      (pair) => pair[0] === name && (value === undefined || pair[1] === String(value)),
    );
  }
  set(key, value) {
    const name = String(key);
    const index = this._pairs.findIndex((pair) => pair[0] === name);
    if (index < 0) {
      this._pairs.push([name, String(value)]);
    } else {
      this._pairs[index] = [name, String(value)];
      this._pairs = this._pairs.filter((pair, i) => i <= index || pair[0] !== name);
    }
    this._changed();
  }
  sort() {
    this._pairs.sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0));
    this._changed();
  }
  get size() {
    return this._pairs.length;
  }
  forEach(fn, thisArg) {
    for (const [key, value] of this._pairs.slice()) fn.call(thisArg, value, key, this);
  }
  *keys() {
    for (const pair of this._pairs.slice()) yield pair[0];
  }
  *values() {
    for (const pair of this._pairs.slice()) yield pair[1];
  }
  *entries() {
    for (const pair of this._pairs.slice()) yield [pair[0], pair[1]];
  }
  [Symbol.iterator]() {
    return this.entries();
  }
  toString() {
    return this._pairs
      .map(([key, value]) => `${encodeComponent(key)}=${encodeComponent(value)}`)
      .join("&");
  }
}

/// 按 application/x-www-form-urlencoded 规则编码单个键或值（空格转 +，并转义 !'()~）。
function encodeComponent(text) {
  return encodeURIComponent(text).replace(/%20/g, "+").replace(/[!'()~]/g, (c) =>
    "%" + c.charCodeAt(0).toString(16).toUpperCase(),
  );
}

/// 对应的解码逻辑，遇到非法百分号序列时原样返回。
function decodeComponent(text) {
  try {
    return decodeURIComponent(String(text).replace(/\+/g, " "));
  } catch {
    return String(text);
  }
}

const URL_RE = /^([A-Za-z][A-Za-z0-9+.-]*:)(\/\/)?([^/?#]*)?([^?#]*)(\?[^#]*)?(#.*)?$/;

/// 层级式 URL 实现：拆解 protocol/host/port/pathname/search/hash，并支持相对 base 解析。
export class URL {
  constructor(input, base) {
    let text = normalizeURLText(input);
    if (base !== undefined && !/^[A-Za-z][A-Za-z0-9+.-]*:/.test(text)) {
      text = resolveRelative(String(base), text);
    }
    if (/^file:/i.test(text)) text = normalizeFileURLInput(text);
    const match = URL_RE.exec(text);
    if (!match) throw new TypeError(`Invalid URL: ${input}`);

    this.protocol = match[1].toLowerCase();
    const authority = match[2] ? match[3] || "" : "";
    this.username = "";
    this.password = "";
    let hostPort = authority;
    let hasExplicitPort = false;
    const at = authority.lastIndexOf("@");
    if (at >= 0) {
      const credentials = authority.slice(0, at);
      hostPort = authority.slice(at + 1);
      const colon = credentials.indexOf(":");
      this.username = colon < 0 ? credentials : credentials.slice(0, colon);
      this.password = colon < 0 ? "" : credentials.slice(colon + 1);
    }
    // IPv6 字面量要保留中括号，不能被其内部的冒号拆开。
    if (hostPort.startsWith("[")) {
      const close = hostPort.indexOf("]");
      this.hostname = hostPort.slice(0, close + 1);
      const suffix = hostPort.slice(close + 1);
      hasExplicitPort = suffix.startsWith(":");
      this.port = suffix.replace(/^:/, "");
    } else {
      const colon = hostPort.lastIndexOf(":");
      hasExplicitPort = colon >= 0;
      this.hostname = (colon < 0 ? hostPort : hostPort.slice(0, colon)).toLowerCase();
      this.port = colon < 0 ? "" : hostPort.slice(colon + 1);
    }
    if (this.protocol === "file:" && hasExplicitPort) throw new TypeError(`Invalid URL: ${input}`);
    if (this.port && SPECIAL_PORTS[this.protocol] === this.port) this.port = "";

    let path = match[4] || "";
    if (match[2] && !path.startsWith("/")) path = "/" + path;
    this.pathname = match[2] ? normalizePath(path, this.protocol === "file:") || "/" : path;
    if (this.protocol === "file:") this.pathname = normalizeWindowsDrive(this.pathname);
    this.hash = match[6] || "";
    this._search = match[5] || "";
    this.searchParams = new URLSearchParams(this._search);
    this.searchParams._owner = this;
  }

  get search() {
    return this._search;
  }
  set search(value) {
    const text = String(value);
    this._search = !text || text === "?" ? "" : text.startsWith("?") ? text : "?" + text;
    this.searchParams._owner = null;
    this.searchParams = new URLSearchParams(this._search);
    this.searchParams._owner = this;
  }
  _syncSearchFromParams() {
    const text = this.searchParams.toString();
    this._search = text ? "?" + text : "";
  }

  get host() {
    return this.port ? `${this.hostname}:${this.port}` : this.hostname;
  }
  set host(value) {
    const text = String(value);
    const colon = text.lastIndexOf(":");
    if (colon > 0 && !text.endsWith("]")) {
      this.hostname = text.slice(0, colon).toLowerCase();
      this.port = text.slice(colon + 1);
    } else {
      this.hostname = text.toLowerCase();
      this.port = "";
    }
  }

  get origin() {
    return this.hostname ? `${this.protocol}//${this.host}` : "null";
  }

  get href() {
    let out = this.protocol;
    if (this.hostname || this.protocol === "file:") {
      out += "//";
      if (this.username) {
        out += this.username;
        if (this.password) out += ":" + this.password;
        out += "@";
      }
      out += this.host;
    }
    return out + this.pathname + this._search + this.hash;
  }
  set href(value) {
    const replacement = new URL(value);
    for (const key of ["protocol", "username", "password", "hostname", "port", "pathname", "hash"]) {
      this[key] = replacement[key];
    }
    this.search = replacement.search;
  }

  toString() {
    return this.href;
  }
  toJSON() {
    return this.href;
  }

  static canParse(input, base) {
    try {
      new URL(input, base);
      return true;
    } catch {
      return false;
    }
  }
}

// GearMac 只运行在 macOS 上，因此这里有意不支持 Node 的 Windows 路径覆盖。
export function fileURLToPath(input, options = {}) {
  let parsed;
  if (typeof input === "string") {
    try {
      parsed = new URL(normalizeFileURLInput(input));
    } catch (error) {
      if (error && error.code === undefined) error.code = "ERR_INVALID_URL";
      throw error;
    }
  } else if (isURL(input)) {
    parsed = input;
  } else {
    throw nodeTypeError(
      "ERR_INVALID_ARG_TYPE",
      'The "path" argument must be of type string or an instance of URL.',
    );
  }
  if (parsed.protocol !== "file:") {
    throw nodeTypeError("ERR_INVALID_URL_SCHEME", "The URL must be of scheme file");
  }
  if (parsed.username || parsed.password || parsed.port) {
    throw nodeTypeError("ERR_INVALID_URL", "Invalid URL");
  }
  if (options?.windows) {
    throw new Error("Windows file paths are not supported in GearMac extensions.");
  }
  const hostname = decodedFileHostname(parsed.hostname);
  if (hostname !== "" && hostname.toLowerCase() !== "localhost") {
    throw nodeTypeError(
      "ERR_INVALID_FILE_URL_HOST",
      'File URL host must be "localhost" or empty on darwin',
    );
  }
  const pathname = String(parsed.pathname);
  if (/%2f/i.test(pathname)) {
    throw nodeTypeError(
      "ERR_INVALID_FILE_URL_PATH",
      "File URL path must not include encoded / characters",
    );
  }
  return pathname.includes("%") ? decodeURIComponent(pathname) : pathname;
}

/// 解析 file URL 的 host 部分：仅在存在百分号编码时才解码并做字符合法性校验。
function decodedFileHostname(value) {
  const encoded = String(value);
  let hostname = encoded;
  if (encoded.includes("%")) {
    try {
      hostname = decodeURIComponent(hostname);
    } catch {
      throw nodeTypeError("ERR_INVALID_URL", "Invalid URL");
    }
    if (/[\u0000-\u0020#%/:<>?@[\\\]^|]/.test(hostname)) {
      throw nodeTypeError("ERR_INVALID_URL", "Invalid URL");
    }
  }
  return hostname;
}

/// 把多种 file URL 写法（单斜杠、反斜杠、Windows 盘符）统一为 file:/// 形式。
function normalizeFileURLInput(input) {
  const text = normalizeURLText(input);
  if (!/^file:/i.test(text)) return text;
  const suffixIndex = text.search(/[?#]/);
  const head = suffixIndex < 0 ? text : text.slice(0, suffixIndex);
  const suffix = suffixIndex < 0 ? "" : text.slice(suffixIndex);
  const normalized = head.replace(/\\/g, "/") + suffix;
  const rest = normalized.slice(5);
  if (/^\/\/[A-Za-z](?::|\|)(?:\/|$)/.test(rest)) return `file:///${rest.slice(2)}`;
  if (rest.startsWith("//")) return `file:${rest}`;
  return rest.startsWith("/") ? `file://${rest}` : `file:///${rest}`;
}

/// 去除输入首尾的控制/空白字符，并删除内部的制表符与换行。
function normalizeURLText(input) {
  return String(input)
    .replace(/^[\u0000-\u0020]+|[\u0000-\u0020]+$/g, "")
    .replace(/[\t\r\n]/g, "");
}

// encodeURI 会保留 ? # ~，因此带这三个字符的文件名会被解析回 query 或 fragment。
export function pathToFileURL(input) {
  const encoded = encodeURI(String(input)).replace(
    /[?#~]/g,
    (char) => "%" + char.charCodeAt(0).toString(16).toUpperCase(),
  );
  return new URL("file://" + encoded);
}

/// 近似判断一个对象是否为 URL 实例（不依赖 instanceof）。
function isURL(value) {
  return Boolean(
    value?.href && value.protocol && value.auth === undefined && value.path === undefined,
  );
}

/// 构造带 `code` 字段的 TypeError，模拟 Node 的错误形状。
function nodeTypeError(code, message) {
  const error = new TypeError(message);
  error.code = code;
  return error;
}

/// 按 `//`、`/`、`?`、`#` 前缀分别解析相对 URL。
function resolveRelative(base, relative) {
  const parsed = new URL(base);
  if (relative.startsWith("//")) return parsed.protocol + relative;
  if (relative.startsWith("/")) return `${parsed.protocol}//${parsed.host}${relative}`;
  if (relative.startsWith("?")) return `${parsed.protocol}//${parsed.host}${parsed.pathname}${relative}`;
  if (relative.startsWith("#")) {
    return `${parsed.protocol}//${parsed.host}${parsed.pathname}${parsed.search}${relative}`;
  }
  const dir = parsed.pathname.replace(/[^/]*$/, "");
  return `${parsed.protocol}//${parsed.host}${normalizePath(
    dir + relative,
    parsed.protocol === "file:",
  )}`;
}

/// 规范化路径：合并 `.` 与 `..` 段；`preservesFileDriveRoot` 用于保留 file: 的盘符根。
function normalizePath(path, preservesFileDriveRoot = false) {
  const leadingSlash = path.startsWith("/");
  const segments = path.split("/");
  const out = [];
  const firstSegment = segments[1] ?? "";
  const driveRoot =
    preservesFileDriveRoot &&
    leadingSlash &&
    (/^[A-Za-z]:/.test(firstSegment) || /^[A-Za-z]\|$/.test(firstSegment));
  for (let index = leadingSlash ? 1 : 0; index < segments.length; index++) {
    const segment = segments[index];
    const dots = segment.replace(/%2e/gi, ".");
    const isLast = index === segments.length - 1;
    if (dots === ".") {
      if (isLast) out.push("");
      continue;
    }
    if (dots === "..") {
      if (out.length > (driveRoot ? 1 : 0)) out.pop();
      if (isLast) out.push("");
      continue;
    }
    out.push(segment);
  }
  let joined = out.join("/");
  if (leadingSlash) joined = "/" + joined;
  return joined || (leadingSlash ? "/" : "");
}

/// 把 file URL 中的 `/C|` 形式修正为 `/C:`。
function normalizeWindowsDrive(pathname) {
  return pathname.replace(/^\/([A-Za-z])\|(?=\/|$)/, "/$1:");
}

if (!globalThis.URL) globalThis.URL = URL;
if (!globalThis.URLSearchParams) globalThis.URLSearchParams = URLSearchParams;
