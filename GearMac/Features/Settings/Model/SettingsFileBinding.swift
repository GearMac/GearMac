// 文件职责：把 settings.json 的单个键绑定到 App 实际存放该值的位置，提供成对的读取与写入闭包。
// 分层：Model；@MainActor，只负责值的读写与拒绝，不直接触碰文件系统。
import Foundation

/// settings.json 中的一个键，绑定到 App 实际保存该值的位置。
@MainActor
struct SettingsFileBinding {
    let key: SettingsFileKey
    let read: () -> SettingsFileJSON
    /// 返回无法使用的部分，其余内容保持不动，因此一个笔误不会让某个设置丢失。
    let write: (SettingsFileJSON) -> [SettingsFileIssue]

    /// 用显式的 read/write 闭包构造绑定。
    init(
        _ key: SettingsFileKey, read: @escaping () -> SettingsFileJSON,
        write: @escaping (SettingsFileJSON) -> [SettingsFileIssue]
    ) {
        self.key = key
        self.read = read
        self.write = write
    }

    /// `accept` 对类型本身允许的值做收窄或规范化，返回 nil 表示拒绝该值。
    init<Root: AnyObject, Value: SettingsFileValue>(
        _ key: SettingsFileKey, _ root: Root, _ path: ReferenceWritableKeyPath<Root, Value>,
        accept: @escaping (Value) -> Value? = { $0 }
    ) {
        self.init(
            key,
            read: { root[keyPath: path].settingsJSON },
            write: { json in
                guard let value = Value(settingsJSON: json).flatMap(accept) else {
                    return [.invalidValue(key)]
                }
                // 赋一个相等的值仍会通知该属性的所有观察者。
                if root[keyPath: path] != value { root[keyPath: path] = value }
                return []
            })
    }
}
