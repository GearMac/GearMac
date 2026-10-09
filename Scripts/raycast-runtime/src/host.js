// 文件职责：封装 JS 运行时与 Swift 宿主之间的唯一调用缝（`__gearmacHost`），提供同步/异步宿主调用与日志、错误描述。
// 分层：Raycast 运行时（宿主桥）；Swift 在求值 bundle 前把 `__gearmacHost` 挂到全局，其余代码一律经由这里。
// JS 运行时与 Swift 之间的唯一接缝。Swift 在求值 bundle 前把 `__gearmacHost` 装到全局，
// 这里的其他内容都通过这些辅助函数转发。

// Swift 注入的宿主对象；缺失说明运行时被在 GearMac 之外求值。
const raw = globalThis.__gearmacHost;
if (!raw) throw new Error("__gearmacHost missing — the runtime was evaluated outside GearMac.");

export const hostRaw = raw;

let nextCallId = 1;
const pending = new Map();

/// 所有触及系统的 Raycast API 都是异步宿主调用：Swift 稍后通过 `__gearmac.settle` 回填结果，
/// 因此 JS 线程永不阻塞等待主 actor。
export function hostCall(api, method, args) {
  return new Promise((resolve, reject) => {
    const callId = nextCallId++;
    pending.set(callId, { resolve, reject });
    try {
      raw.invoke(String(callId), api, method, JSON.stringify(args === undefined ? [] : args));
    } catch (error) {
      pending.delete(callId);
      reject(error);
    }
  });
}

/// 同步版本，仅供 Node 垫片使用（fs、child_process、crypto、zlib）。之所以安全，是因为 Swift 完全在 JS
/// 线程上服务这些调用——不会跳到主 actor，因此同步返回不会与 UI 死锁。
export function hostCallSync(api, method, args) {
  const json = hostRaw.invokeSync(api, method, JSON.stringify(args === undefined ? [] : args));
  const result = json ? JSON.parse(json) : { ok: true };
  if (result.ok) return result.value;
  const error = new Error(String(result.error || `${api}.${method} failed`));
  if (result.code) error.code = result.code;
  if (result.errno !== undefined) error.errno = result.errno;
  if (result.path) error.path = result.path;
  throw error;
}

/// 由 Swift 调用：按 callId 结算一个挂起的宿主调用（成功则 resolve，失败则 reject）。
export function settle(callId, ok, payload) {
  const entry = pending.get(Number(callId));
  if (!entry) return;
  pending.delete(Number(callId));
  if (ok) {
    entry.resolve(payload === undefined || payload === "" ? undefined : JSON.parse(payload));
  } else {
    entry.reject(new Error(String(payload || "Host call failed")));
  }
}

/// 把日志参数序列化后转交 Swift 输出。
export function log(level, parts) {
  let text;
  try {
    text = parts.map(formatLogArg).join(" ");
  } catch {
    text = "[unserializable log argument]";
  }
  raw.log(level, text);
}

/// 把任意日志参数转成可读字符串。
function formatLogArg(value) {
  if (typeof value === "string") return value;
  if (value instanceof Error) return describeError(value);
  if (value === undefined) return "undefined";
  try {
    return JSON.stringify(value);
  } catch {
    return String(value);
  }
}

/// JavaScriptCore 的 `Error.stack` 只有调用帧——不像 V8 会重复消息——因此必须前置标题行，
/// 否则记录下来的错误只会剩下一串调用帧。
export function describeError(error) {
  if (!(error instanceof Error)) return String(error);
  const headline = `${error.name || "Error"}: ${error.message}`;
  const stack = String(error.stack || "");
  if (!stack) return headline;
  return stack.startsWith(headline) ? stack : `${headline}\n${stack}`;
}
