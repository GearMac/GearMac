// 文件职责：通过合成 Dock 滑动手势切换 Space，从而让 macOS 跳过自带的滑动过渡动画。
// 分层：Service；@MainActor 隔离，同一时刻只允许一个手势，避免 Dock 一次移动两个 Space。
import CoreGraphics
import Foundation

/// 通过合成 Dock 滑动手势切换 Space，从而让 macOS 跳过自带的滑动过渡动画。
@MainActor
final class SpaceSwitcher {
    /// 是否需要该 payload 取决于运行中的系统，因此无法用 `#available` 判定。
    private nonisolated static let augmentsEvents = ProcessInfo.processInfo.isOperatingSystemAtLeast(
        OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0))

    private var gesture: Task<Void, Never>?

    /// 与第一个手势重叠的第二个手势会让 Dock 一次移动两个 Space，因此被丢弃。
    func perform(_ direction: SpaceDirection) {
        guard gesture == nil, Permissions.ensureAccessibility() else { return }
        gesture = Task {
            await Self.post(direction)
            gesture = nil
        }
    }

    /// 用户首次修改之前该键不存在，而 macOS 默认视为开启。
    private nonisolated static var naturalScrolling: Bool {
        UserDefaults.standard.object(forKey: "com.apple.swipescrolldirection") as? Bool ?? true
    }

    private nonisolated static func post(_ direction: SpaceDirection) async {
        // macOS 27 会把自然滚动应用到合成滑动上，因此这里把方向符号反转回来。
        let direction = augmentsEvents && naturalScrolling ? direction.reversed : direction
        for phase in SpaceGesture.Phase.allCases {
            guard let event = event(phase: phase, direction: direction) else { return }
            event.post(tap: .cgSessionEventTap)
            guard augmentsEvents, phase != .ended else { continue }
            try? await Task.sleep(for: SpaceGesture.phaseDelay)
        }
    }

    private nonisolated static func event(
        phase: SpaceGesture.Phase, direction: SpaceDirection
    ) -> CGEvent? {
        guard let event = CGEvent(source: nil) else { return nil }
        // 新建的事件不带时间戳，而缺少它就无法构建 payload。
        let timestamp = mach_absolute_time()
        let fields = SpaceGesture.fields(
            phase: phase, direction: direction, augmented: augmentsEvents, timestamp: timestamp)
        for field in fields {
            guard let key = CGEventField(rawValue: field.raw) else { continue }
            switch field.value {
            case .integer(let value): event.setIntegerValueField(key, value: value)
            case .double(let value): event.setDoubleValueField(key, value: value)
            }
        }
        guard augmentsEvents else { return event }
        let payload = SpaceGesture.payload(
            phase: phase, direction: direction, timestamp: timestamp)
        return augmented(event, payload: payload)
    }

    /// 没有 setter 能到达字段 4205，因此把 payload 拼接进序列化后的事件里。
    private nonisolated static func augmented(_ event: CGEvent, payload: Data) -> CGEvent? {
        guard var bytes = event.__data(allocator: nil) as Data?,
            bytes.starts(with: SpaceGesture.dataVersion)
        else { return nil }
        bytes.append(contentsOf: SpaceGesture.payloadRecordHeader(payloadCount: payload.count))
        bytes.append(payload)
        return CGEvent(withDataAllocator: nil, data: bytes as CFData)
    }
}
