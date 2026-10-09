// 文件职责：定义 settings.json 值与内存类型互转的协议（SettingsFileValue）及 Bool/Int/String/Array/Optional 的实现。
// 分层：Model；初始化器返回 nil 表示拒绝该值，而非猜测或使用默认值。
import Foundation

/// settings.json 持有的一个值；初始化器返回 `nil` 表示拒绝该值，而不是猜测。
protocol SettingsFileValue: Equatable {
    init?(settingsJSON: SettingsFileJSON)
    var settingsJSON: SettingsFileJSON { get }
}

/// 在文件中以其 rawValue 表示的枚举。
protocol SettingsFileRawValue: SettingsFileValue, RawRepresentable
where RawValue: SettingsFileValue {}

extension SettingsFileRawValue {
    init?(settingsJSON: SettingsFileJSON) {
        guard let rawValue = RawValue(settingsJSON: settingsJSON) else { return nil }
        self.init(rawValue: rawValue)
    }

    var settingsJSON: SettingsFileJSON { rawValue.settingsJSON }
}

/// 通过自身映射表在文件中表示的枚举，因此哨兵值读起来是一个词。
protocol SettingsFileToken: SettingsFileValue, CaseIterable {
    /// 由构造保证穷尽：新增 case 若未给出其拼写就无法通过编译。
    var settingsToken: SettingsFileJSON { get }
}

extension SettingsFileToken {
    init?(settingsJSON: SettingsFileJSON) {
        guard let match = Self.allCases.first(where: { $0.settingsToken == settingsJSON }) else {
            return nil
        }
        self = match
    }

    var settingsJSON: SettingsFileJSON { settingsToken }
}

extension Bool: SettingsFileValue {
    init?(settingsJSON: SettingsFileJSON) {
        guard let value = settingsJSON.bool else { return nil }
        self = value
    }

    var settingsJSON: SettingsFileJSON { .bool(self) }
}

extension Int: SettingsFileValue {
    init?(settingsJSON: SettingsFileJSON) {
        guard let value = settingsJSON.int else { return nil }
        self = value
    }

    var settingsJSON: SettingsFileJSON { .number(Double(self)) }
}

extension String: SettingsFileValue {
    init?(settingsJSON: SettingsFileJSON) {
        guard let value = settingsJSON.string else { return nil }
        self = value
    }

    var settingsJSON: SettingsFileJSON { .string(self) }
}

/// 全有或全无：任一元素非法即拒绝整个列表，因此笔误不会悄悄缩短列表。
extension Array: SettingsFileValue where Element: SettingsFileValue {
    init?(settingsJSON: SettingsFileJSON) {
        guard let items = settingsJSON.items else { return nil }
        var values: [Element] = []
        values.reserveCapacity(items.count)
        for item in items {
            guard let value = Element(settingsJSON: item) else { return nil }
            values.append(value)
        }
        self = values
    }

    var settingsJSON: SettingsFileJSON { .array(map(\.settingsJSON)) }
}

extension Optional: SettingsFileValue where Wrapped: SettingsFileValue {
    init?(settingsJSON: SettingsFileJSON) {
        if settingsJSON == .null {
            self = .none
            return
        }
        guard let value = Wrapped(settingsJSON: settingsJSON) else { return nil }
        self = .some(value)
    }

    var settingsJSON: SettingsFileJSON { map(\.settingsJSON) ?? .null }
}
