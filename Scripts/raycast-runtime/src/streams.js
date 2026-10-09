// 文件职责：实现 Node 的 stream 核心（Readable / Writable / Duplex / Transform / PassThrough 与 pipeline）。
// 分层：运行时模块（Raycast JS runtime）；提供真实契约而非近似替代，供扩展的 stream-chain / stream-json 使用。
//
// 解析大型 JSON 索引的扩展会带上 `stream-chain` + `stream-json`，它们构造真正的对象模式管线：
// 从 options 生成 `Duplex`、`Transform` 子类在 `_transform` 中 `push`、`pipe` 串联，以及用 `push()` 返回 false 停止上游。
// 只有真正的契约能承载这些用法，因此这里是契约本身而非占位实现。
//
// 一处有意的简化：`Transform` 在 `_transform` 回调后即确认写入，而不等待其可读侧腾出空间。
// `pipe` 仍会在目标写满时暂停上游，因此管线规模有界；只有无人读取的 transform 会持续增长。

import { Buffer } from "./buffer.js";
import { EventEmitter } from "./events.js";
import { ReadableStream } from "./web-streams.js";

const ignore = () => {};

/// 计算 chunk 的长度：对象模式下固定为 1，否则取字符串或字节长度。
function sizeOf(chunk, objectMode) {
  if (objectMode) return 1;
  return typeof chunk === "string" ? chunk.length : (chunk?.length ?? 0);
}

/// Node 的遗留基类。`module.exports = Stream`，打包产物依赖这一点：
/// node-fetch 在构建每个 Request 时都测试 `body instanceof stream.default`。
export class Stream extends EventEmitter {}

/// 可读流：提供 push/read/pipe 与流动、暂停两种消费方式。
export class Readable extends Stream {
  constructor(options = {}) {
    super();
    const objectMode = options.readableObjectMode ?? options.objectMode ?? false;
    this._readableState = {
      readable: true,
      objectMode,
      highWaterMark: options.highWaterMark ?? (objectMode ? 16 : 16 * 1024),
      buffer: [],
      length: 0,
      encoding: options.encoding ?? null,
      flowing: false,
      reading: false,
      ended: false,
      endEmitted: false,
      destroyed: false,
      scheduled: false,
      waiter: null,
    };
    if (options.read) this._read = options.read;
    if (options.destroy) this._destroy = options.destroy;
  }

  get readable() {
    return !this._readableState.endEmitted && !this._readableState.destroyed;
  }
  get readableEnded() {
    return this._readableState.endEmitted;
  }
  get readableFlowing() {
    return this._readableState.flowing;
  }
  get readableObjectMode() {
    return this._readableState.objectMode;
  }
  get readableLength() {
    return this._readableState.length;
  }
  get destroyed() {
    return this._readableState.destroyed;
  }

  _read() {}

  push(chunk, encoding) {
    const state = this._readableState;
    state.reading = false;
    if (state.ended || state.destroyed) return false;
    if (chunk === null || chunk === undefined) {
      state.ended = true;
      this._schedule();
      return false;
    }
    if (!state.objectMode) {
      if (typeof chunk === "string") chunk = Buffer.from(chunk, encoding || "utf8");
      else if (!(chunk instanceof Buffer)) chunk = Buffer.from(chunk);
      if (state.encoding) chunk = chunk.toString(state.encoding);
    }
    if (!sizeOf(chunk, state.objectMode)) return true;
    state.buffer.push(chunk);
    state.length += sizeOf(chunk, state.objectMode);
    this._schedule();
    return state.length < state.highWaterMark;
  }

  read() {
    const state = this._readableState;
    if (!state.buffer.length) {
      this._pull();
      return null;
    }
    const chunk = state.buffer.shift();
    state.length -= sizeOf(chunk, state.objectMode);
    this._pull();
    return chunk;
  }

  setEncoding(encoding) {
    this._readableState.encoding = encoding;
    return this;
  }

  resume() {
    this._readableState.flowing = true;
    this._schedule();
    return this;
  }

  pause() {
    this._readableState.flowing = false;
    return this;
  }

  isPaused() {
    return !this._readableState.flowing;
  }

  on(event, listener) {
    super.on(event, listener);
    if (event === "data") this.resume();
    else if (event === "readable") this._schedule();
    return this;
  }

  pipe(destination) {
    const resume = () => this.resume();
    this.on("data", (chunk) => {
      if (destination.write(chunk) === false) {
        this.pause();
        destination.once("drain", resume);
      }
    });
    this.on("end", () => destination.end?.());
    this.on("error", (error) => destination.destroy?.(error));
    return destination;
  }

  unpipe() {
    return this.pause();
  }

  destroy(error) {
    const state = this._readableState;
    if (state.destroyed) return this;
    state.destroyed = true;
    state.readable = false;
    state.buffer.length = 0;
    state.length = 0;
    this._wake();
    const close = (reason) => {
      if (reason) this.emit("error", reason);
      this.emit("close");
    };
    if (this._destroy) this._destroy(error ?? null, close);
    else close(error);
    return this;
  }

  async *[Symbol.asyncIterator]() {
    const state = this._readableState;
    for (;;) {
      if (state.buffer.length) {
        yield this.read();
        continue;
      }
      if (state.ended || state.destroyed) return;
      this._pull();
      if (!state.buffer.length && !state.ended && !state.destroyed) {
        await new Promise((resolve) => (state.waiter = resolve));
      }
    }
  }

  /// 仅在缓冲区有空间、且没有尚未完成的读取请求时，才向源请求更多数据。
  _pull() {
    const state = this._readableState;
    if (state.reading || state.ended || state.destroyed) return;
    if (state.length >= state.highWaterMark) return;
    state.reading = true;
    try {
      this._read(state.highWaterMark);
    } catch (error) {
      state.reading = false;
      this.destroy(error);
    }
  }

  _wake() {
    const waiter = this._readableState.waiter;
    if (!waiter) return;
    this._readableState.waiter = null;
    waiter();
  }

  /// 像 Node 一样延后一个 tick 投递：先 push 再 end 的生产者不能跑在它的监听器之前。
  _schedule() {
    const state = this._readableState;
    this._wake();
    if (state.scheduled || state.destroyed) return;
    state.scheduled = true;
    queueMicrotask(() => {
      state.scheduled = false;
      if (state.destroyed) return;
      while (state.flowing && state.buffer.length) this.emit("data", this.read());
      if (state.buffer.length) this.emit("readable");
      if (state.ended && !state.buffer.length && !state.endEmitted) {
        state.endEmitted = true;
        state.readable = false;
        this.emit("end");
        this.emit("close");
      } else {
        this._pull();
      }
    });
  }
}

Readable.from = (iterable, options) => {
  // Node 会把字符串或 Buffer 当作单个 chunk；直接迭代它们会得到字符或裸字节数值。
  if (typeof iterable === "string" || iterable instanceof Uint8Array) iterable = [iterable];
  const iterator = iterable[Symbol.asyncIterator]?.() ?? iterable[Symbol.iterator]();
  return new Readable({
    objectMode: true,
    ...options,
    async read() {
      try {
        const { value, done } = await iterator.next();
        this.push(done ? null : value);
      } catch (error) {
        this.destroy(error);
      }
    },
  });
};

Readable.fromWeb = (stream, options) => {
  const reader = stream.getReader();
  return new Readable({
    ...options,
    async read() {
      try {
        const { value, done } = await reader.read();
        this.push(done ? null : value);
      } catch (error) {
        this.destroy(error);
      }
    },
    destroy(error, close) {
      reader.cancel(error ?? undefined).catch(ignore);
      close(error);
    },
  });
};

Readable.toWeb = (readable) =>
  new ReadableStream({
    start(controller) {
      readable.on("data", (chunk) => controller.enqueue(chunk));
      readable.on("end", () => controller.close());
      readable.on("error", (error) => controller.error(error));
    },
    cancel: (reason) => readable.destroy(reason),
  });

/// 初始化可写侧状态与可选的 `_write`/`_final`/`_destroy` 实现，供 Writable 与 Duplex 共用。
function initWritable(stream, options) {
  const objectMode = options.writableObjectMode ?? options.objectMode ?? false;
  stream._writableState = {
    writable: true,
    objectMode,
    highWaterMark: options.highWaterMark ?? (objectMode ? 16 : 16 * 1024),
    buffer: [],
    length: 0,
    defaultEncoding: options.defaultEncoding ?? "utf8",
    pumping: false,
    needDrain: false,
    ending: false,
    ended: false,
    finished: false,
    destroyed: false,
  };
  if (options.write) stream._write = options.write;
  if (options.final) stream._final = options.final;
  if (options.destroy) stream._destroy = options.destroy;
}

/// 可写流：提供 write/end 与背压（drain）通知。
export class Writable extends Stream {
  constructor(options = {}) {
    super();
    initWritable(this, options);
  }

  get writable() {
    return !this._writableState.ending && !this._writableState.destroyed;
  }
  get writableEnded() {
    return this._writableState.ending;
  }
  get writableFinished() {
    return this._writableState.finished;
  }
  get writableObjectMode() {
    return this._writableState.objectMode;
  }
  get writableLength() {
    return this._writableState.length;
  }

  _write(chunk, encoding, callback) {
    callback(new Error("_write() is not implemented on this stream."));
  }

  _final(callback) {
    callback(null);
  }

  write(chunk, encoding, callback) {
    if (typeof encoding === "function") {
      callback = encoding;
      encoding = null;
    }
    const state = this._writableState;
    if (state.ending || state.destroyed) {
      queueMicrotask(() => callback?.(new Error("write after end")));
      return false;
    }
    state.buffer.push({ chunk, encoding: encoding ?? state.defaultEncoding, callback });
    state.length += sizeOf(chunk, state.objectMode);
    // 先占定 drain 状态再开始泵送：同步的 `_write` 会在本次调用内把队列清空。
    const room = state.length < state.highWaterMark;
    state.needDrain = state.needDrain || !room;
    this._pump();
    return room;
  }

  end(chunk, encoding, callback) {
    if (typeof chunk === "function") return this.end(null, null, chunk);
    if (typeof encoding === "function") return this.end(chunk, null, encoding);
    if (chunk !== null && chunk !== undefined) this.write(chunk, encoding);
    if (callback) this.once("finish", () => callback(null));
    this._writableState.ending = true;
    this._pump();
    return this;
  }

  cork() {}
  uncork() {}

  destroy(error) {
    const state = this._writableState;
    if (state.destroyed) return this;
    state.destroyed = true;
    state.writable = false;
    state.buffer.length = 0;
    const close = (reason) => {
      if (reason) this.emit("error", reason);
      this.emit("close");
    };
    if (this._destroy) this._destroy(error ?? null, close);
    else close(error);
    return this;
  }

  /// 同一时刻只允许一个 `_write` 在途；下一个从它的回调开始，因此写入保持顺序。
  _pump() {
    const state = this._writableState;
    if (state.pumping) return;
    state.pumping = true;
    const step = () => {
      if (state.destroyed) {
        state.pumping = false;
        return;
      }
      const entry = state.buffer.shift();
      if (!entry) {
        state.pumping = false;
        // 像 Node 一样延后一个 tick：`pipe` 只在 `write` 返回之后才挂上 drain 监听器。
        if (state.needDrain) {
          state.needDrain = false;
          queueMicrotask(() => this.emit("drain"));
        }
        if (state.ending && !state.ended) this._finishWrites();
        return;
      }
      state.length -= sizeOf(entry.chunk, state.objectMode);
      let settled = false;
      const done = (error) => {
        if (settled) return;
        settled = true;
        entry.callback?.(error ?? null);
        if (error) {
          state.pumping = false;
          this.destroy(error);
          return;
        }
        step();
      };
      try {
        this._write(entry.chunk, entry.encoding, done);
      } catch (error) {
        done(error);
      }
    };
    step();
  }

  _finishWrites() {
    const state = this._writableState;
    state.ended = true;
    this._final((error) => {
      if (error) return this.destroy(error);
      state.finished = true;
      state.writable = false;
      this.emit("finish");
    });
  }
}

Writable.fromWeb = (stream, options) => {
  const writer = stream.getWriter();
  return new Writable({
    ...options,
    write(chunk, encoding, callback) {
      writer.write(chunk).then(() => callback(null), callback);
    },
    final(callback) {
      writer.close().then(() => callback(null), callback);
    },
  });
};

// Node 构建 `Duplex` 的方式相同：继承 `Readable`，再把整个可写半边借过来。
/// 读写双向流：继承 Readable 并复用 Writable 的方法与访问器。
export class Duplex extends Readable {
  constructor(options = {}) {
    super(options);
    initWritable(this, options);
    if (options.read) this._read = options.read;
  }

  destroy(error) {
    this._writableState.destroyed = true;
    this._writableState.writable = false;
    this._writableState.buffer.length = 0;
    return Readable.prototype.destroy.call(this, error);
  }
}

for (const name of ["_write", "_final", "write", "end", "cork", "uncork", "_pump", "_finishWrites"]) {
  Duplex.prototype[name] = Writable.prototype[name];
}
for (const name of ["writable", "writableEnded", "writableFinished", "writableObjectMode", "writableLength"]) {
  Object.defineProperty(Duplex.prototype, name, Object.getOwnPropertyDescriptor(Writable.prototype, name));
}

Duplex.fromWeb = (pair, options) => {
  const source = Readable.fromWeb(pair.readable, options);
  const writer = pair.writable.getWriter();
  const duplex = new Duplex({
    ...options,
    read: () => source.resume(),
    write(chunk, encoding, callback) {
      writer.write(chunk).then(() => callback(null), callback);
    },
    final(callback) {
      writer.close().then(() => callback(null), callback);
    },
  });
  source.on("data", (chunk) => duplex.push(chunk));
  source.on("end", () => duplex.push(null));
  source.on("error", (error) => duplex.destroy(error));
  return duplex;
};

/// 变换流：以 `_transform`/`_flush` 将写入的数据变换后 push 到可读侧。
export class Transform extends Duplex {
  constructor(options = {}) {
    super(options);
    if (options.transform) this._transform = options.transform;
    if (options.flush) this._flush = options.flush;
  }

  _transform(chunk, encoding, callback) {
    callback(null, chunk);
  }

  _flush(callback) {
    callback(null);
  }

  _write(chunk, encoding, callback) {
    this._transform(chunk, encoding, (error, data) => {
      if (data !== null && data !== undefined) this.push(data);
      callback(error ?? null);
    });
  }

  _final(callback) {
    this._flush((error, data) => {
      if (data !== null && data !== undefined) this.push(data);
      if (!error) this.push(null);
      callback(error ?? null);
    });
  }
}

/// 透传流：不做任何变换的 Transform。
export class PassThrough extends Transform {}

/// 把多个流依次 pipe 并用 Promise 表达完成；任一阶段出错则销毁全部阶段。
export function pipelinePromise(stages) {
  return new Promise((resolve, reject) => {
    let settled = false;
    const fail = (error) => {
      if (settled) return;
      settled = true;
      for (const stage of stages) stage.destroy?.();
      reject(error instanceof Error ? error : new Error(String(error)));
    };
    for (const stage of stages) stage.on?.("error", fail);
    const last = stages.reduce((from, to) => from.pipe(to));
    const done = () => {
      if (settled) return;
      settled = true;
      resolve();
    };
    if (last._writableState) last.on("finish", done);
    else last.on("end", done);
  });
}

/// 回调版 pipeline：回调放在参数末尾，因此 `util.promisify(stream.pipeline)` 可用；
/// `stream/promises` 等待的是同一个核心实现。
export function pipeline(...stages) {
  const callback = typeof stages[stages.length - 1] === "function" ? stages.pop() : ignore;
  const last = stages[stages.length - 1];
  pipelinePromise(stages).then(() => callback(null), callback);
  return last;
}

/// 监听流的 error/close/finish/end，把它们归一为一次完成通知。
function onFinished(stream, settle) {
  stream.on("error", settle);
  stream.on("close", () => settle(null));
  stream.on("finish", () => settle(null));
  stream.on("end", () => settle(null));
}

/// 回调版 finished：仅在首次完成时调用回调。
export function finished(stream, callback) {
  let settled = false;
  onFinished(stream, (error) => {
    if (settled) return;
    settled = true;
    callback?.(error ?? null);
  });
}

/// Promise 版 finished：完成时 resolve，出错时 reject。
export function finishedPromise(stream) {
  return new Promise((resolve, reject) => onFinished(stream, (error) => (error ? reject(error) : resolve())));
}
