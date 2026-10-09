// 文件职责：持久化用户为各个扩展指定的外观覆盖项（按扩展名存入 UserDefaults）。
// 分层：Service；只依赖 Foundation/UserDefaults，不得 import AppKit/SwiftUI。
import Foundation

/// 扩展外观覆盖存储：与 preferences 一样以 manifest name 为键，因此重装扩展后外观选择仍会保留。
@MainActor
@Observable
final class ExtensionAppearanceStore {
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let key = "extensionAppearances"

    private(set) var overrides: [String: ExtensionAppearance]

    init() {
        if let data = defaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode([String: ExtensionAppearance].self, from: data)
        {
            overrides = decoded
        } else {
            overrides = [:]
        }
    }

    /// 返回该扩展已设置的外观覆盖项；未设置时返回 nil。
    func appearance(for extensionName: String) -> ExtensionAppearance? {
        overrides[extensionName]
    }

    /// 设置或清除外观覆盖；传入 `nil` 时恢复扩展自带的图标。
    func set(_ appearance: ExtensionAppearance?, for extensionName: String) {
        if let appearance {
            overrides[extensionName] = appearance
        } else {
            overrides.removeValue(forKey: extensionName)
        }
        persist()
    }

    /// 把当前覆盖表编码后写入 UserDefaults。
    private func persist() {
        guard let data = try? JSONEncoder().encode(overrides) else { return }
        defaults.set(data, forKey: key)
    }
}
