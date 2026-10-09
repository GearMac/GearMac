// 文件职责：定义七维量纲向量 CalcDimension，用于表达式求值时的量纲加减与幂运算。
// 分层：Model；纯值类型（Hashable/Sendable），所有运算保持各分量相互独立。
/// 各基本量纲上的指数向量，相等即量纲一致。
struct CalcDimension: Hashable, Sendable {
    var length = 0.0
    var mass = 0.0
    var time = 0.0
    var data = 0.0
    var electricCurrent = 0.0
    var pixels = 0.0
    var currency = 0.0

    /// 无量纲（纯数量）的零向量。
    static let scalar = CalcDimension()

    /// 逐分量相加，`scale` 用于做减法或反向运算。
    func adding(_ other: Self, scale: Double = 1) -> Self {
        Self(
            length: length + other.length * scale, mass: mass + other.mass * scale,
            time: time + other.time * scale, data: data + other.data * scale,
            electricCurrent: electricCurrent + other.electricCurrent * scale,
            pixels: pixels + other.pixels * scale, currency: currency + other.currency * scale)
    }

    /// 各分量乘以幂指数，用于 `m^2` 一类的量纲升降幂。
    func raised(to power: Double) -> Self {
        Self(
            length: length * power, mass: mass * power, time: time * power, data: data * power,
            electricCurrent: electricCurrent * power, pixels: pixels * power, currency: currency * power)
    }
}
