// 文件职责：为 raycast-runtime 提供最小可用的 WHATWG Streams 实现（ReadableStream / WritableStream / TransformStream）及字节流互转工具，支撑 `fetch` 响应体的读取、管道与异步迭代。
// 分层：运行时 polyfill（JS 运行时层）；纯 JS 实现，经 host call 与宿主交互，不得直接依赖 AppKit/SwiftUI。
// WHATWG streams，只实现 `fetch` body 所需的部分形状：`getReader`、`pipeThrough`、`pipeTo`、
// 异步迭代以及中间插入的 `TransformStream`。不含 byte streams、BYOB 与 `tee`。

/// 用于吞掉无需处理的 Promise 拒绝，避免产生未处理的 rejection 告警。
const ignore = () => {};

/// ReadableStream 的默认控制器：向消费者入队数据块，并将流置为结束或错误状态。
class ReadableStreamDefaultController {
  constructor(stream) {
    this._stream = stream;
  }
  get desiredSize() {
    return this._stream._done ? 0 : this._stream._highWaterMark - this._stream._queue.length;
  }
  enqueue(chunk) {
    this._stream._enqueue(chunk);
  }
  close() {
    this._stream._finish();
  }
  error(reason) {
    this._stream._fail(reason);
  }
}

/// ReadableStream 的默认读取器：串行取走数据块，并负责加锁与释放锁。
class ReadableStreamDefaultReader {
  constructor(stream) {
    if (stream.locked) throw new TypeError("ReadableStream is already locked.");
    stream._locked = true;
    this._stream = stream;
    this.closed = stream._closed;
  }
  read() {
    return this._stream._take();
  }
  cancel(reason) {
    return this._stream.cancel(reason);
  }
  releaseLock() {
    this._stream._locked = false;
  }
}

/// 最小实现的 ReadableStream：以「队列 + 等待者」承载 source 主动推送或 pull 拉取的数据块。
export class ReadableStream {
  constructor(source = {}, strategy = {}) {
    this._source = source;
    this._queue = [];
    this._waiters = [];
    this._done = false;
    this._failure = null;
    this._locked = false;
    this._pulling = false;
    this._highWaterMark = strategy.highWaterMark ?? 1;
    this._controller = new ReadableStreamDefaultController(this);
    this._closed = new Promise((resolve, reject) => {
      this._settleClosed = resolve;
      this._rejectClosed = reject;
    });
    this._closed.catch(ignore);
    try {
      Promise.resolve(source.start?.(this._controller)).catch((reason) => this._fail(reason));
    } catch (error) {
      this._fail(error);
    }
  }

  get locked() {
    return this._locked;
  }

  getReader(options) {
    if (options?.mode) throw new TypeError(`Unsupported ReadableStream reader mode: ${options.mode}`);
    return new ReadableStreamDefaultReader(this);
  }

  pipeThrough(transform, options) {
    this.pipeTo(transform.writable, options).catch(ignore);
    return transform.readable;
  }

  async pipeTo(destination, options = {}) {
    const writer = destination.getWriter();
    this._locked = true;
    try {
      for (;;) {
        const { value, done } = await this._take();
        if (done) break;
        await writer.write(value);
      }
      if (!options.preventClose) await writer.close();
    } catch (error) {
      if (!options.preventAbort) await writer.abort(error).catch(ignore);
      throw error;
    } finally {
      this._locked = false;
      writer.releaseLock();
    }
  }

  async cancel(reason) {
    if (!this._done && !this._failure) {
      this._done = true;
      this._queue.length = 0;
      for (const waiter of this._waiters.splice(0)) waiter.resolve({ value: undefined, done: true });
      this._settleClosed();
    }
    await this._source.cancel?.(reason);
  }

  async *[Symbol.asyncIterator]() {
    for (;;) {
      const { value, done } = await this._take();
      if (done) return;
      yield value;
    }
  }

  _take() {
    if (this._queue.length) return Promise.resolve({ value: this._queue.shift(), done: false });
    if (this._failure) return Promise.reject(this._failure);
    if (this._done) return Promise.resolve({ value: undefined, done: true });
    const chunk = new Promise((resolve, reject) => this._waiters.push({ resolve, reject }));
    this._pull();
    return chunk;
  }

  /// 同一时刻只允许一个 `pull` 在途；若其结束后仍有等待者缺数据，则立即再发起一次。
  _pull() {
    if (this._pulling || this._done || this._failure || !this._source.pull) return;
    this._pulling = true;
    Promise.resolve()
      .then(() => this._source.pull(this._controller))
      .then(() => {
        this._pulling = false;
        if (this._waiters.length && !this._queue.length) this._pull();
      }, (reason) => this._fail(reason));
  }

  _enqueue(chunk) {
    if (this._done || this._failure) return;
    const waiter = this._waiters.shift();
    if (waiter) waiter.resolve({ value: chunk, done: false });
    else this._queue.push(chunk);
  }

  _finish() {
    if (this._done || this._failure) return;
    this._done = true;
    for (const waiter of this._waiters.splice(0)) waiter.resolve({ value: undefined, done: true });
    this._settleClosed();
  }

  _fail(reason) {
    if (this._done || this._failure) return;
    this._failure = reason instanceof Error ? reason : new Error(String(reason));
    for (const waiter of this._waiters.splice(0)) waiter.reject(this._failure);
    this._rejectClosed(this._failure);
  }
}

/// WritableStream 的默认控制器：把流置为错误状态。
class WritableStreamDefaultController {
  constructor(stream) {
    this._stream = stream;
  }
  error(reason) {
    this._stream._fail(reason);
  }
}

/// WritableStream 的默认写入器：串行写入、关闭、终止，并管理流的锁。
class WritableStreamDefaultWriter {
  constructor(stream) {
    if (stream.locked) throw new TypeError("WritableStream is already locked.");
    stream._locked = true;
    this._stream = stream;
    this.closed = stream._closed;
    this.desiredSize = 1;
    this.ready = Promise.resolve();
  }
  write(chunk) {
    return this._stream._push(chunk);
  }
  close() {
    return this._stream.close();
  }
  abort(reason) {
    return this._stream.abort(reason);
  }
  releaseLock() {
    this._stream._locked = false;
  }
}

// `pipeTo` 会等待每一次写入完成，因此 sink 自身无需队列即可保持顺序。
// 最小实现的 WritableStream：按调用顺序把数据块交给 sink 的 `write`，并跟踪关闭与错误状态。
export class WritableStream {
  constructor(sink = {}) {
    this._sink = sink;
    this._locked = false;
    this._failure = null;
    this._controller = new WritableStreamDefaultController(this);
    this._closed = new Promise((resolve, reject) => {
      this._settleClosed = resolve;
      this._rejectClosed = reject;
    });
    this._closed.catch(ignore);
    Promise.resolve(sink.start?.(this._controller)).catch((reason) => this._fail(reason));
  }

  get locked() {
    return this._locked;
  }

  getWriter() {
    return new WritableStreamDefaultWriter(this);
  }

  async _push(chunk) {
    if (this._failure) throw this._failure;
    await this._sink.write?.(chunk, this._controller);
  }

  async close() {
    if (this._failure) throw this._failure;
    await this._sink.close?.();
    this._settleClosed();
  }

  async abort(reason) {
    this._fail(reason);
    await this._sink.abort?.(reason);
  }

  _fail(reason) {
    if (this._failure) return;
    this._failure = reason instanceof Error ? reason : new Error(String(reason));
    this._rejectClosed(this._failure);
  }
}

/// 在可写端接收数据块交给 transformer 转换，再把转换结果推入可读端。
export class TransformStream {
  constructor(transformer = {}, _writableStrategy = {}, readableStrategy = {}) {
    let controller;
    const readable = new ReadableStream({ start: (given) => (controller = given) }, readableStrategy);
    this.readable = readable;
    this.writable = new WritableStream({
      write: (chunk) =>
        transformer.transform ? transformer.transform(chunk, controller) : controller.enqueue(chunk),
      close: async () => {
        await transformer.flush?.(controller);
        controller.close();
      },
      abort: (reason) => readable._fail(reason),
    });
    Promise.resolve(transformer.start?.(controller)).catch((reason) => readable._fail(reason));
  }
}

/// 构造 `fetch` 响应体：字节数据已全部到达，因此该「流」只按读取粒度分片交出。
export function readableStreamOfBytes(bytes, chunkSize = 65536) {
  let offset = 0;
  return new ReadableStream({
    pull(controller) {
      if (offset >= bytes.length) return controller.close();
      controller.enqueue(bytes.slice(offset, offset + chunkSize));
      offset += chunkSize;
    },
  });
}

/// 把可读流完整读干并拼接为单个 Uint8Array；非 Uint8Array 的数据块按文本编码处理。
export async function bytesOfReadableStream(stream) {
  const chunks = [];
  let length = 0;
  for await (const chunk of stream) {
    const bytes = chunk instanceof Uint8Array ? chunk : new TextEncoder().encode(String(chunk));
    chunks.push(bytes);
    length += bytes.length;
  }
  const joined = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    joined.set(chunk, offset);
    offset += chunk.length;
  }
  return joined;
}
