// 文件职责：实现 Node `events` 模块的 EventEmitter 及其静态方法。
// 分层：Raycast 运行时（Node 内置垫片）；单独成文件是为了打破 `node-shims` → 流核心 → `events` 的导入环。
// Node 的 `events`。它单独成文件，是因为流核心建立在它之上、`node-shims` 又建立在流核心之上，
// 若放在 `node-shims` 里会形成导入环。

// 与 Node 实现一致，事件状态按需惰性创建。
/// Node 风格的事件发射器，是 `events` 模块的核心。
export class EventEmitter {
  constructor() {
    this._events = new Map();
    this._maxListeners = undefined;
  }
  /// 返回某事件的监听器数组，不存在时惰性创建。
  _list(event) {
    const events = (this._events ??= new Map());
    if (!events.has(event)) events.set(event, []);
    return events.get(event);
  }
  on(event, listener) {
    this._list(event).push(listener);
    return this;
  }
  addListener(event, listener) {
    return this.on(event, listener);
  }
  prependListener(event, listener) {
    this._list(event).unshift(listener);
    return this;
  }
  /// 注册只触发一次的监听器；包装函数保留原 `listener` 引用，便于用原始函数移除。
  once(event, listener) {
    const wrapper = (...args) => {
      this.off(event, wrapper);
      listener.apply(this, args);
    };
    wrapper.listener = listener;
    return this.on(event, wrapper);
  }
  off(event, listener) {
    const list = this._events?.get(event);
    if (!list) return this;
    const index = list.findIndex((entry) => entry === listener || entry.listener === listener);
    if (index >= 0) list.splice(index, 1);
    return this;
  }
  removeListener(event, listener) {
    return this.off(event, listener);
  }
  removeAllListeners(event) {
    if (event === undefined) this._events?.clear();
    else this._events?.delete(event);
    return this;
  }
  emit(event, ...args) {
    const list = this._events?.get(event);
    if (!list?.length) return false;
    for (const listener of list.slice()) listener.apply(this, args);
    return true;
  }
  listenerCount(event) {
    return this._events?.get(event)?.length ?? 0;
  }
  listeners(event) {
    return (this._events?.get(event) ?? []).slice();
  }
  eventNames() {
    return this._events ? Array.from(this._events.keys()) : [];
  }
  setMaxListeners(count) {
    this._maxListeners = count;
    return this;
  }
  getMaxListeners() {
    return this._maxListeners ?? EventEmitter.defaultMaxListeners;
  }
}

// 兼容 Node 的静态属性与方法；GearMac 不做全局监听器上限限制。
EventEmitter.EventEmitter = EventEmitter;
EventEmitter.defaultMaxListeners = 10;
EventEmitter.setMaxListeners = () => {};
/// 兼容 Node API：signal 中止时调用 listener，返回可释放的句柄。
EventEmitter.addAbortListener = (signal, listener) => (signal.addEventListener("abort", listener), { [Symbol.dispose]: () => signal.removeEventListener("abort", listener) });
/// 兼容 Node API：把事件流转成 AsyncIterator，可选的 signal 中止后结束迭代。
EventEmitter.on = (emitter, event, { signal } = {}) => {
  const queue = [], waiters = [], listener = (...args) => waiters.length ? waiters.shift()({ value: args, done: false }) : queue.push(args);
  const stop = () => { emitter.off(event, listener); while (waiters.length) waiters.shift()({ done: true }); };
  emitter.on(event, listener);
  signal?.addEventListener("abort", stop, { once: true });
  return { [Symbol.asyncIterator]() { return this; }, next() { return queue.length ? Promise.resolve({ value: queue.shift(), done: false }) : signal?.aborted ? Promise.resolve({ done: true }) : new Promise(resolve => waiters.push(resolve)); }, return() { stop(); return Promise.resolve({ done: true }); } };
};
/// 兼容 Node API：返回一个在事件首次触发时 resolve 的 Promise。
EventEmitter.once = (emitter, event) =>
  new Promise((resolve) => emitter.once(event, (...args) => resolve(args)));
