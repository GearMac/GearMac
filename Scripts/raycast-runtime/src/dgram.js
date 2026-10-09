// 文件职责：实现 `dgram` 的极小子集，只服务 multicast-dns 解析 `.local` 主机名这一种场景。
// 分层：Raycast 运行时（Node 内置垫片）；socket 从不真正联网，查询转发给系统解析器。
// `dgram` 只为一种情况存在：multicast-dns 解析 `.local` 主机。socket 从不真正走到网络——
// mDNSResponder 已经应答这些查询，所以请求改发给系统解析器。

import { Buffer } from "./buffer.js";
import { EventEmitter } from "./events.js";
import { hostCall } from "./host.js";

// mDNS 端口，以及 A 记录 / 任意记录 / IN 类别的常量。
const MDNS_PORT = 5353;
const A_RECORD = 1;
const ANY_RECORD = 255;
const IN_CLASS = 1;

/// 伪 UDP socket：把 mDNS 查询转成系统 DNS 解析，再构造应答报文回送给上层。
class NameLookupSocket extends EventEmitter {
  constructor() {
    super();
    this.port = MDNS_PORT;
    this.closed = false;
  }

  /// 兼容 Node 的参数重载（port/address 位置都可能是 callback）。
  bind(port, address, callback) {
    if (typeof port === "function") return this.bind(undefined, undefined, port);
    if (typeof address === "function") return this.bind(port, undefined, address);
    if (typeof port === "number") this.port = port;
    if (callback) this.once("listening", callback);
    setTimeout(() => this.emit("listening"), 0);
    return this;
  }

  address() {
    return { address: "0.0.0.0", port: this.port, family: "IPv4" };
  }

  /// 只接受 mDNS 端口；把查询报文交给系统解析器并异步回送应答。
  send(buffer, offset = 0, length, port, address, callback) {
    if (port !== MDNS_PORT) {
      throw new Error("dgram only answers mDNS name lookups in GearMac extensions. See docs/extensions.md.");
    }
    const packet = Buffer.from(buffer);
    this.answer(packet.subarray(offset, offset + (length ?? packet.length)));
    callback?.(null);
    return this;
  }

  close(callback) {
    if (this.closed) return this;
    this.closed = true;
    if (callback) this.once("close", callback);
    setTimeout(() => this.emit("close"), 0);
    return this;
  }

  // 组播由解析器负责，因此加入组等操作都是空实现，仅为兼容 Node socket 接口。
  addMembership() {}
  dropMembership() {}
  setMulticastTTL() {}
  setMulticastLoopback() {}
  setMulticastInterface() {}
  setTTL() {}
  ref() {
    return this;
  }
  unref() {
    return this;
  }

  /// 解析查询报文并逐条回送 A 记录应答。
  async answer(packet) {
    const query = decodeQuery(packet);
    if (!query) return;
    const answers = [];
    for (const question of query.questions) {
      if (question.class !== IN_CLASS) continue;
      if (question.type !== A_RECORD && question.type !== ANY_RECORD) continue;
      const addresses = await hostCall("dns", "resolve", [question.name]).catch(() => []);
      for (const address of addresses) answers.push({ name: question.name, address });
    }
    // 保持静默，等同于该名字在网络中无人认领。
    if (this.closed || !answers.length) return;
    const response = encodeResponse(packet, query, answers);
    this.emit("message", response, {
      address: "127.0.0.1", family: "IPv4", port: this.port, size: response.length
    });
  }
}

/// 解析 mDNS 查询报文，返回问题列表；格式不符合本实现支持的范围时返回 null。
function decodeQuery(packet) {
  if (packet.length < 12) return null;
  const count = packet.readUInt16BE(4);
  const questions = [];
  let offset = 12;
  for (let index = 0; index < count; index++) {
    const labels = [];
    for (;;) {
      if (offset >= packet.length) return null;
      const size = packet[offset];
      // 查询不会压缩名字，因此出现指针就说明这不是我们要应答的报文。
      if (size >= 0xc0) return null;
      offset += 1;
      if (size === 0) break;
      labels.push(packet.subarray(offset, offset + size).toString("utf8"));
      offset += size;
    }
    if (offset + 4 > packet.length) return null;
    questions.push({
      name: labels.join("."),
      type: packet.readUInt16BE(offset),
      class: packet.readUInt16BE(offset + 2) & 0x7fff,
    });
    offset += 4;
  }
  return questions.length ? { id: packet.readUInt16BE(0), questions, end: offset } : null;
}

/// 构造 mDNS 应答报文（头部加上各条应答记录）。
function encodeResponse(packet, query, answers) {
  const header = Buffer.alloc(12);
  header.writeUInt16BE(query.id, 0);
  header.writeUInt16BE(0x8400, 2);
  header.writeUInt16BE(query.questions.length, 4);
  header.writeUInt16BE(answers.length, 6);
  return Buffer.concat([header, packet.subarray(12, query.end), ...answers.map(encodeRecord)]);
}

/// 编码一条 A 记录（IPv4 地址），TTL 固定为 120 秒。
function encodeRecord({ name, address }) {
  const record = Buffer.alloc(14);
  record.writeUInt16BE(A_RECORD, 0);
  record.writeUInt16BE(1, 2);
  record.writeUInt32BE(120, 4);
  record.writeUInt16BE(4, 8);
  address.split(".").forEach((part, index) => (record[10 + index] = Number(part)));
  return Buffer.concat([encodeName(name), record]);
}

/// 按 DNS 标签格式编码域名。
function encodeName(name) {
  const labels = name.split(".").filter(Boolean);
  const out = Buffer.alloc(labels.reduce((total, label) => total + label.length + 1, 1));
  let offset = 0;
  for (const label of labels) {
    out[offset] = label.length;
    out.write(label, offset + 1);
    offset += label.length + 1;
  }
  return out;
}

/// `dgram` 模块导出对象。
export const dgram = {
  /// 创建伪 mDNS socket，并把传入的 message 监听器挂上。
  createSocket(options, listener) {
    const socket = new NameLookupSocket();
    const handler = typeof options === "function" ? options : listener;
    if (handler) socket.on("message", handler);
    return socket;
  },
  Socket: NameLookupSocket,
};
