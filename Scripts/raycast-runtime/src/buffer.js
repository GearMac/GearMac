// 文件职责：基于 Uint8Array 实现 Node `Buffer` 的子集，覆盖扩展 bundle 用到的编解码与二进制解析。
// 分层：Raycast 运行时（Node 内置垫片）；刻意不提供任何流式能力，支持范围见 docs/extensions.md。
// 基于 Uint8Array 的 Buffer 子集——足以覆盖 bundle 做的编解码与二进制解析。
// 任何与流相关的形态都刻意缺失；支持范围见 docs/extensions.md。

import { base64ToBytes, bytesToBase64, utf8Decode, utf8Encode } from "./polyfills.js";

/// 十六进制字符串转字节数组，忽略非十六进制字符。
function hexToBytes(text) {
  const clean = String(text).replace(/[^0-9a-fA-F]/g, "");
  const out = new Uint8Array(clean.length >> 1);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(clean.substr(i * 2, 2), 16);
  return out;
}

/// 字节数组转小写十六进制字符串。
function bytesToHex(bytes) {
  let out = "";
  for (const byte of bytes) out += byte.toString(16).padStart(2, "0");
  return out;
}

/// 字符串按 latin1/ASCII 语义转字节（取每字符低 8 位）。
function latin1ToBytes(text) {
  const out = new Uint8Array(text.length);
  for (let i = 0; i < text.length; i++) out[i] = text.charCodeAt(i) & 0xff;
  return out;
}

/// 字节按 latin1 语义转字符串。
function bytesToLatin1(bytes) {
  let out = "";
  for (const byte of bytes) out += String.fromCharCode(byte);
  return out;
}

/// 把各种编码别名归一化到内部使用的规范名（无法识别时回退 utf8）。
function normalizeEncoding(encoding) {
  const name = String(encoding || "utf8").toLowerCase();
  if (name === "utf-8" || name === "utf8") return "utf8";
  if (name === "base64" || name === "base64url") return name;
  if (name === "hex") return "hex";
  if (name === "latin1" || name === "binary" || name === "ascii") return "latin1";
  if (name === "utf16le" || name === "ucs2" || name === "ucs-2" || name === "utf-16le") return "utf16le";
  return "utf8";
}

/// 按编码把字节解码为字符串。
function decode(bytes, encoding) {
  switch (normalizeEncoding(encoding)) {
    case "base64":
      return bytesToBase64(bytes);
    case "base64url":
      return bytesToBase64(bytes).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
    case "hex":
      return bytesToHex(bytes);
    case "latin1":
      return bytesToLatin1(bytes);
    case "utf16le": {
      let out = "";
      for (let i = 0; i + 1 < bytes.length; i += 2) out += String.fromCharCode(bytes[i] | (bytes[i + 1] << 8));
      return out;
    }
    default:
      return utf8Decode(bytes);
  }
}

/// 按编码把字符串编码为字节。
function encode(text, encoding) {
  switch (normalizeEncoding(encoding)) {
    case "base64":
    case "base64url":
      return base64ToBytes(String(text).replace(/-/g, "+").replace(/_/g, "/"));
    case "hex":
      return hexToBytes(text);
    case "latin1":
      return latin1ToBytes(String(text));
    case "utf16le": {
      const source = String(text);
      const out = new Uint8Array(source.length * 2);
      for (let i = 0; i < source.length; i++) {
        const code = source.charCodeAt(i);
        out[i * 2] = code & 0xff;
        out[i * 2 + 1] = code >> 8;
      }
      return out;
    }
    default:
      return utf8Encode(String(text));
  }
}

/// 按字典序比较两个字节序列，返回 -1/0/1。
function compareBytes(a, b) {
  const shared = Math.min(a.length, b.length);
  for (let i = 0; i < shared; i++) if (a[i] !== b[i]) return a[i] < b[i] ? -1 : 1;
  if (a.length === b.length) return 0;
  return a.length < b.length ? -1 : 1;
}

/// 基于同一底层 ArrayBuffer 构造 DataView，用于浮点读写。
function dataViewOf(buffer) {
  return new DataView(buffer.buffer, buffer.byteOffset, buffer.byteLength);
}

/// 校验 offset 与其后的 ext 字节是否落在 length 范围内，越界则抛出带 code 的 RangeError（与 Node 一致）。
function checkSpan(offset, ext, length) {
  const at = Number(offset) | 0;
  if (!Number.isInteger(Number(offset)) || at < 0 || at + ext > length) {
    const error = new RangeError(`The value of "offset" is out of range. It must be >= 0 and <= ${length - ext}. Received ${offset}`);
    error.code = "ERR_OUT_OF_RANGE";
    throw error;
  }
  return at;
}

/// 校验整数取值范围，越界则抛出 ERR_OUT_OF_RANGE。
function checkInt(value, min, max, name) {
  if (typeof value !== "number" || !Number.isInteger(value) || value < min || value > max) {
    const error = new RangeError(`The value of "${name}" is out of range. It must be >= ${min} and <= ${max}. Received ${value}`);
    error.code = "ERR_OUT_OF_RANGE";
    throw error;
  }
}

/// 通用小端无符号整数读取（1–6 字节）。
function readUIntLEGeneric(buffer, offset, byteLength) {
  const at = checkSpan(offset, byteLength, buffer.length);
  if (byteLength < 1 || byteLength > 6) throw new RangeError("byteLength must be 1-6");
  let value = 0;
  for (let i = byteLength - 1; i >= 0; i--) value = value * 256 + buffer[at + i];
  return value;
}

/// 通用大端无符号整数读取（1–6 字节）。
function readUIntBEGeneric(buffer, offset, byteLength) {
  const at = checkSpan(offset, byteLength, buffer.length);
  if (byteLength < 1 || byteLength > 6) throw new RangeError("byteLength must be 1-6");
  let value = 0;
  for (let i = 0; i < byteLength; i++) value = value * 256 + buffer[at + i];
  return value;
}

/// 通用小端有符号整数读取，根据最高位判断负数。
function readIntLEGeneric(buffer, offset, byteLength) {
  const unsigned = readUIntLEGeneric(buffer, offset, byteLength);
  const limit = 2 ** (8 * byteLength - 1);
  return unsigned >= limit ? unsigned - 2 ** (8 * byteLength) : unsigned;
}

/// 通用大端有符号整数读取，根据最高位判断负数。
function readIntBEGeneric(buffer, offset, byteLength) {
  const unsigned = readUIntBEGeneric(buffer, offset, byteLength);
  const limit = 2 ** (8 * byteLength - 1);
  return unsigned >= limit ? unsigned - 2 ** (8 * byteLength) : unsigned;
}

/// 通用小端无符号整数写入，返回写入后的偏移。
function writeUIntLEGeneric(buffer, value, offset, byteLength) {
  const at = checkSpan(offset, byteLength, buffer.length);
  checkInt(value, 0, 2 ** (8 * byteLength) - 1, "value");
  let rest = value;
  for (let i = 0; i < byteLength; i++) {
    buffer[at + i] = rest & 0xff;
    rest = Math.floor(rest / 256);
  }
  return at + byteLength;
}

/// 通用大端无符号整数写入，返回写入后的偏移。
function writeUIntBEGeneric(buffer, value, offset, byteLength) {
  const at = checkSpan(offset, byteLength, buffer.length);
  checkInt(value, 0, 2 ** (8 * byteLength) - 1, "value");
  let rest = value;
  for (let i = byteLength - 1; i >= 0; i--) {
    buffer[at + i] = rest & 0xff;
    rest = Math.floor(rest / 256);
  }
  return at + byteLength;
}

/// Node `Buffer` 的子集实现，直接继承 Uint8Array 以复用底层视图语义。
export class Buffer extends Uint8Array {
  /// 兼容 Node 的 Buffer.from：支持字符串、ArrayBuffer、Uint8Array、数组及 Buffer.toJSON 结果。
  static from(value, encodingOrOffset, length) {
    if (typeof value === "string") return wrap(encode(value, encodingOrOffset));
    if (value instanceof ArrayBuffer) {
      return wrap(
        new Uint8Array(
          value,
          encodingOrOffset || 0,
          length === undefined ? value.byteLength - (encodingOrOffset || 0) : length,
        ),
      );
    }
    if (value instanceof Uint8Array) return wrap(new Uint8Array(value));
    if (Array.isArray(value)) return wrap(new Uint8Array(value));
    if (value && typeof value === "object" && value.type === "Buffer" && Array.isArray(value.data)) {
      return wrap(new Uint8Array(value.data));
    }
    throw new TypeError("Buffer.from: unsupported input");
  }

  /// 分配指定大小的 Buffer，可选用填充值（undefined 与 0 均视为不填充）。
  static alloc(size, fill) {
    const bytes = new Uint8Array(Math.max(0, size | 0));
    if (fill !== undefined && fill !== 0) {
      const value = typeof fill === "number" ? fill : encode(String(fill), "utf8")[0] ?? 0;
      bytes.fill(value & 0xff);
    }
    return wrap(bytes);
  }

  /// GearMac 不做内存池，allocUnsafe 与 alloc 等价。
  static allocUnsafe(size) {
    return Buffer.alloc(size);
  }

  /// 同 allocUnsafe，仅为兼容 API。
  static allocUnsafeSlow(size) {
    return Buffer.alloc(size);
  }

  /// 拼接多个 Buffer/Uint8Array，可指定总长度。
  static concat(list, totalLength) {
    const parts = list.map((part) => (part instanceof Uint8Array ? part : Buffer.from(part)));
    const total = totalLength === undefined ? parts.reduce((sum, part) => sum + part.length, 0) : totalLength;
    const out = new Uint8Array(total);
    let offset = 0;
    for (const part of parts) {
      if (offset >= total) break;
      out.set(part.subarray(0, Math.min(part.length, total - offset)), offset);
      offset += part.length;
    }
    return wrap(out);
  }

  /// 判断是否为 Buffer；GearMac 中 Buffer 即 Uint8Array，因此两者等价。
  static isBuffer(value) {
    return value instanceof Uint8Array;
  }

  /// 静态比较两个 Buffer 的字节序。
  static compare(a, b) {
    if (!(a instanceof Uint8Array) || !(b instanceof Uint8Array)) {
      throw new TypeError("Buffer.compare: inputs must be Buffers");
    }
    return compareBytes(a, b);
  }

  /// 判断编码名是否受支持。
  static isEncoding(encoding) {
    const name = String(encoding || "").toLowerCase();
    return ["utf8", "utf-8", "base64", "base64url", "hex", "latin1", "binary", "ascii", "utf16le", "ucs2", "ucs-2", "utf-16le"].includes(name);
  }

  /// 返回字符串按指定编码的字节长度（非字符串则取其 length）。
  static byteLength(value, encoding) {
    if (typeof value === "string") return encode(value, encoding).length;
    return value?.length ?? 0;
  }

  /// 按编码把 [start, end) 区间解码为字符串。
  toString(encoding, start, end) {
    const view = this.subarray(start ?? 0, end ?? this.length);
    return decode(view, encoding);
  }

  /// 序列化为 `{ type: "Buffer", data: [...] }`。
  toJSON() {
    return { type: "Buffer", data: Array.from(this) };
  }

  /// 逐字节比较两个 Buffer 是否相等。
  equals(other) {
    if (!(other instanceof Uint8Array) || other.length !== this.length) return false;
    for (let i = 0; i < this.length; i++) if (this[i] !== other[i]) return false;
    return true;
  }

  /// 与目标 Buffer 的指定区间比较。
  compare(target, targetStart, targetEnd, sourceStart, sourceEnd) {
    if (!(target instanceof Uint8Array)) throw new TypeError("Buffer.compare: target must be a Buffer");
    const targetSlice = target.subarray(targetStart ?? 0, targetEnd ?? target.length);
    const sourceSlice = this.subarray(sourceStart ?? 0, sourceEnd ?? this.length);
    return compareBytes(sourceSlice, targetSlice);
  }

  /// 把本 Buffer 的一段复制到目标 Buffer，返回复制的字节数。
  copy(target, targetStart = 0, sourceStart = 0, sourceEnd = this.length) {
    if (!(target instanceof Uint8Array)) throw new TypeError("Buffer.copy: target must be a Buffer");
    const count = Math.min(sourceEnd - sourceStart, target.length - targetStart);
    if (count <= 0) return 0;
    target.set(this.subarray(sourceStart, sourceStart + count), targetStart);
    return count;
  }

  /// 返回子视图，并嫁接回 Buffer 原型。
  subarray(start, end) {
    return wrap(super.subarray(start, end));
  }

  /// 把字符串写入指定偏移，返回实际写入的字节数。
  write(text, offset = 0, length, encoding) {
    if (typeof length === "string") {
      encoding = length;
      length = undefined;
    }
    const bytes = encode(text, encoding);
    const count = Math.min(length ?? bytes.length, this.length - offset);
    this.set(bytes.subarray(0, count), offset);
    return count;
  }

  // 以下为各类型定长读取，offset 越界统一抛出带 ERR_OUT_OF_RANGE 的 RangeError。
  readUInt8(offset = 0) {
    return this[checkSpan(offset, 1, this.length)];
  }

  readInt8(offset = 0) {
    const at = checkSpan(offset, 1, this.length);
    return (this[at] << 24) >> 24;
  }

  readUInt16LE(offset = 0) {
    const at = checkSpan(offset, 2, this.length);
    return this[at] | (this[at + 1] << 8);
  }

  readUInt16BE(offset = 0) {
    const at = checkSpan(offset, 2, this.length);
    return (this[at] << 8) | this[at + 1];
  }

  readInt16LE(offset = 0) {
    const value = this.readUInt16LE(offset);
    return value >= 0x8000 ? value - 0x10000 : value;
  }

  readInt16BE(offset = 0) {
    const value = this.readUInt16BE(offset);
    return value >= 0x8000 ? value - 0x10000 : value;
  }

  readUInt32LE(offset = 0) {
    const at = checkSpan(offset, 4, this.length);
    return (this[at] | (this[at + 1] << 8) | (this[at + 2] << 16)) + this[at + 3] * 0x1000000;
  }

  readUInt32BE(offset = 0) {
    const at = checkSpan(offset, 4, this.length);
    return this[at] * 0x1000000 + ((this[at + 1] << 16) | (this[at + 2] << 8) | this[at + 3]);
  }

  readInt32LE(offset = 0) {
    const at = checkSpan(offset, 4, this.length);
    return this[at] | (this[at + 1] << 8) | (this[at + 2] << 16) | (this[at + 3] << 24);
  }

  readInt32BE(offset = 0) {
    const at = checkSpan(offset, 4, this.length);
    return (this[at] << 24) | (this[at + 1] << 16) | (this[at + 2] << 8) | this[at + 3];
  }

  readFloatLE(offset = 0) {
    return dataViewOf(this).getFloat32(checkSpan(offset, 4, this.length), true);
  }

  readFloatBE(offset = 0) {
    return dataViewOf(this).getFloat32(checkSpan(offset, 4, this.length), false);
  }

  readDoubleLE(offset = 0) {
    return dataViewOf(this).getFloat64(checkSpan(offset, 8, this.length), true);
  }

  readDoubleBE(offset = 0) {
    return dataViewOf(this).getFloat64(checkSpan(offset, 8, this.length), false);
  }

  readBigUInt64LE(offset = 0) {
    const at = checkSpan(offset, 8, this.length);
    let value = 0n;
    for (let i = 7; i >= 0; i--) value = (value << 8n) | BigInt(this[at + i]);
    return value;
  }

  readBigUInt64BE(offset = 0) {
    const at = checkSpan(offset, 8, this.length);
    let value = 0n;
    for (let i = 0; i < 8; i++) value = (value << 8n) | BigInt(this[at + i]);
    return value;
  }

  readBigInt64LE(offset = 0) {
    const unsigned = this.readBigUInt64LE(offset);
    return unsigned >= 1n << 63n ? unsigned - (1n << 64n) : unsigned;
  }

  readBigInt64BE(offset = 0) {
    const unsigned = this.readBigUInt64BE(offset);
    return unsigned >= 1n << 63n ? unsigned - (1n << 64n) : unsigned;
  }

  // 1–6 字节的通用定点读取。
  readUIntLE(offset, byteLength) {
    return readUIntLEGeneric(this, offset, byteLength);
  }

  readUIntBE(offset, byteLength) {
    return readUIntBEGeneric(this, offset, byteLength);
  }

  readIntLE(offset, byteLength) {
    return readIntLEGeneric(this, offset, byteLength);
  }

  readIntBE(offset, byteLength) {
    return readIntBEGeneric(this, offset, byteLength);
  }

  // 以下为各类型定长写入，返回值均为写入后的新偏移。
  writeUInt8(value, offset = 0) {
    checkInt(value, 0, 0xff, "value");
    this[checkSpan(offset, 1, this.length)] = value;
    return offset + 1;
  }

  writeInt8(value, offset = 0) {
    checkInt(value, -0x80, 0x7f, "value");
    this[checkSpan(offset, 1, this.length)] = value & 0xff;
    return offset + 1;
  }

  writeUInt16LE(value, offset = 0) {
    checkInt(value, 0, 0xffff, "value");
    const at = checkSpan(offset, 2, this.length);
    this[at] = value & 0xff;
    this[at + 1] = (value >> 8) & 0xff;
    return at + 2;
  }

  writeUInt16BE(value, offset = 0) {
    checkInt(value, 0, 0xffff, "value");
    const at = checkSpan(offset, 2, this.length);
    this[at] = (value >> 8) & 0xff;
    this[at + 1] = value & 0xff;
    return at + 2;
  }

  writeInt16LE(value, offset = 0) {
    checkInt(value, -0x8000, 0x7fff, "value");
    return this.writeUInt16LE(value & 0xffff, offset);
  }

  writeInt16BE(value, offset = 0) {
    checkInt(value, -0x8000, 0x7fff, "value");
    return this.writeUInt16BE(value & 0xffff, offset);
  }

  writeUInt32LE(value, offset = 0) {
    checkInt(value, 0, 0xffffffff, "value");
    const at = checkSpan(offset, 4, this.length);
    this[at] = value & 0xff;
    this[at + 1] = (value >> 8) & 0xff;
    this[at + 2] = (value >> 16) & 0xff;
    this[at + 3] = Math.floor(value / 0x1000000) & 0xff;
    return at + 4;
  }

  writeUInt32BE(value, offset = 0) {
    checkInt(value, 0, 0xffffffff, "value");
    const at = checkSpan(offset, 4, this.length);
    this[at] = Math.floor(value / 0x1000000) & 0xff;
    this[at + 1] = (value >> 16) & 0xff;
    this[at + 2] = (value >> 8) & 0xff;
    this[at + 3] = value & 0xff;
    return at + 4;
  }

  writeInt32LE(value, offset = 0) {
    checkInt(value, -0x80000000, 0x7fffffff, "value");
    return this.writeUInt32LE(value >>> 0, offset);
  }

  writeInt32BE(value, offset = 0) {
    checkInt(value, -0x80000000, 0x7fffffff, "value");
    return this.writeUInt32BE(value >>> 0, offset);
  }

  writeFloatLE(value, offset = 0) {
    dataViewOf(this).setFloat32(checkSpan(offset, 4, this.length), Number(value), true);
    return offset + 4;
  }

  writeFloatBE(value, offset = 0) {
    dataViewOf(this).setFloat32(checkSpan(offset, 4, this.length), Number(value), false);
    return offset + 4;
  }

  writeDoubleLE(value, offset = 0) {
    dataViewOf(this).setFloat64(checkSpan(offset, 8, this.length), Number(value), true);
    return offset + 8;
  }

  writeDoubleBE(value, offset = 0) {
    dataViewOf(this).setFloat64(checkSpan(offset, 8, this.length), Number(value), false);
    return offset + 8;
  }

  writeBigUInt64LE(value, offset = 0) {
    let rest = BigInt(value);
    const at = checkSpan(offset, 8, this.length);
    for (let i = 0; i < 8; i++) {
      this[at + i] = Number(rest & 0xffn);
      rest >>= 8n;
    }
    return at + 8;
  }

  writeBigUInt64BE(value, offset = 0) {
    let rest = BigInt(value);
    const at = checkSpan(offset, 8, this.length);
    for (let i = 7; i >= 0; i--) {
      this[at + i] = Number(rest & 0xffn);
      rest >>= 8n;
    }
    return at + 8;
  }

  writeBigInt64LE(value, offset = 0) {
    return this.writeBigUInt64LE(BigInt.asUintN(64, BigInt(value)), offset);
  }

  writeBigInt64BE(value, offset = 0) {
    return this.writeBigUInt64BE(BigInt.asUintN(64, BigInt(value)), offset);
  }

  // 通用定点写入。
  writeUIntLE(value, offset, byteLength) {
    return writeUIntLEGeneric(this, value, offset, byteLength);
  }

  writeUIntBE(value, offset, byteLength) {
    return writeUIntBEGeneric(this, value, offset, byteLength);
  }

  writeIntLE(value, offset, byteLength) {
    const at = checkSpan(offset, byteLength, this.length);
    const limit = 2 ** (8 * byteLength - 1);
    checkInt(value, -limit, limit - 1, "value");
    return writeUIntLEGeneric(this, value < 0 ? value + 2 ** (8 * byteLength) : value, at, byteLength);
  }

  writeIntBE(value, offset, byteLength) {
    const at = checkSpan(offset, byteLength, this.length);
    const limit = 2 ** (8 * byteLength - 1);
    checkInt(value, -limit, limit - 1, "value");
    return writeUIntBEGeneric(this, value < 0 ? value + 2 ** (8 * byteLength) : value, at, byteLength);
  }

  /// 原地按 16 位交换字节序，要求长度是 2 的倍数。
  swap16() {
    if (this.length % 2 !== 0) throw new RangeError("Buffer size must be a multiple of 16-bits");
    for (let i = 0; i < this.length; i += 2) {
      const head = this[i];
      this[i] = this[i + 1];
      this[i + 1] = head;
    }
    return this;
  }

  /// 原地按 32 位交换字节序，要求长度是 4 的倍数。
  swap32() {
    if (this.length % 4 !== 0) throw new RangeError("Buffer size must be a multiple of 32-bits");
    for (let i = 0; i < this.length; i += 4) {
      const a = this[i];
      const b = this[i + 1];
      this[i] = this[i + 3];
      this[i + 1] = this[i + 2];
      this[i + 2] = b;
      this[i + 3] = a;
    }
    return this;
  }

  /// 原地按 64 位交换字节序，要求长度是 8 的倍数。
  swap64() {
    if (this.length % 8 !== 0) throw new RangeError("Buffer size must be a multiple of 64-bits");
    for (let i = 0; i < this.length; i += 8) {
      for (let j = 0; j < 4; j++) {
        const head = this[i + j];
        this[i + j] = this[i + 7 - j];
        this[i + 7 - j] = head;
      }
    }
    return this;
  }

  /// 用给定值填充区间；字符串填充会循环重复其字节。
  fill(value, offset = 0, end = this.length, encoding) {
    if (typeof value === "string") {
      const bytes = encode(value, encoding);
      if (!bytes.length) return this;
      const from = Math.max(0, offset);
      const to = Math.min(this.length, end);
      for (let i = from; i < to; i++) this[i] = bytes[(i - from) % bytes.length];
      return this;
    }
    return super.fill(value ?? 0, offset, end);
  }

  /// 返回切片视图（与 subarray 一样是视图而非拷贝）。
  slice(start, end) {
    return wrap(this.subarray(start, end));
  }
}

// 为 Node 历史上的 `Uint` 拼写别名（如 readUint8）指向同一实现。
for (const [from, to] of [
  ["readUInt8", "readUint8"],
  ["readUInt16LE", "readUint16LE"],
  ["readUInt16BE", "readUint16BE"],
  ["readUInt32LE", "readUint32LE"],
  ["readUInt32BE", "readUint32BE"],
  ["readUIntLE", "readUintLE"],
  ["readUIntBE", "readUintBE"],
  ["writeUInt8", "writeUint8"],
  ["writeUInt16LE", "writeUint16LE"],
  ["writeUInt16BE", "writeUint16BE"],
  ["writeUInt32LE", "writeUint32LE"],
  ["writeUInt32BE", "writeUint32BE"],
  ["writeUIntLE", "writeUintLE"],
  ["writeUIntBE", "writeUintBE"],
]) {
  Buffer.prototype[to] = Buffer.prototype[from];
}

// Node 的静态方法可枚举；safer-buffer 会按 `for…in` 复制它们，否则只能裸调用 Buffer。
for (const name of Object.getOwnPropertyNames(Buffer)) {
  if (typeof Buffer[name] === "function") Object.defineProperty(Buffer, name, { enumerable: true });
}

/// `new Uint8Array(...)` 的结果需要嫁接 Buffer 原型：若改为继承 Uint8Array 再拷贝，
/// 大负载下的每次分配都会翻倍。
function wrap(bytes) {
  Object.setPrototypeOf(bytes, Buffer.prototype);
  return bytes;
}

/// `buffer` 模块导出对象：Buffer、atob/btoa、长度常量与判定函数。
export const bufferModule = {
  Buffer,
  SlowBuffer: Buffer,
  atob: globalThis.atob,
  btoa: globalThis.btoa,
  constants: { MAX_LENGTH: 0x7fffffff, MAX_STRING_LENGTH: 0x1fffffe8 },
  kMaxLength: 0x7fffffff,
  isEncoding: (encoding) => Buffer.isEncoding(encoding),
  isBuffer: (value) => Buffer.isBuffer(value),
};
