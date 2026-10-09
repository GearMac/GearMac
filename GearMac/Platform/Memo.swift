// 文件职责：提供单槽缓存（memo）值类型，用键相等性判断是否复用已构建的值。
// 分层：Model；纯值语义，不依赖 AppKit/SwiftUI。
/// 单槽 memo。键必须包含所有依赖项，因为除此之外没有任何机制会使其失效。
struct Memo<Key: Equatable, Value> {
    private var slot: (key: Key, value: Value)?

    /// 键相同时返回已缓存的值，否则用 `build` 重新构建并替换缓存。
    mutating func value(for key: Key, build: () -> Value) -> Value {
        if let slot, slot.key == key { return slot.value }
        let built = build()
        slot = (key, built)
        return built
    }
}
