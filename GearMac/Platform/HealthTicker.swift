// 文件职责：提供一个共享的 1 秒心跳定时器，驱动多个事件监听器的健康检查。
// 分层：Service；@MainActor，订阅者弱引用，无订阅时不保留定时器。
import Foundation

/// 需要被健康心跳驱动的对象应遵循的协议。
@MainActor
protocol HealthCheckable: AnyObject {
    /// 周期性校验自身监听是否仍然生效，失效时自行恢复。
    func healthCheck()
}

/// 各事件监听器共享的 1 秒看门狗。订阅者弱引用，且无订阅时不保留定时器。
@MainActor
final class HealthTicker {
    /// 弱引用包装，避免订阅者被心跳持有而无法释放。
    private struct WeakSubscriber {
        weak var value: (any HealthCheckable)?
    }

    private var subscribers: [ObjectIdentifier: WeakSubscriber] = [:]
    private var timer: Timer?

    /// 注册订阅者；首个订阅者到来时才创建定时器。
    func subscribe(_ subscriber: any HealthCheckable) {
        subscribers[ObjectIdentifier(subscriber)] = WeakSubscriber(value: subscriber)
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // 用于恢复而非降低延迟：容差允许内核把空闲唤醒合并。
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// 注销订阅者并清理空闲的定时器。
    func unsubscribe(_ subscriber: any HealthCheckable) {
        subscribers.removeValue(forKey: ObjectIdentifier(subscriber))
        stopIfIdle()
    }

    /// 一次心跳：逐个回调存活订阅者，顺便清理已释放的订阅。
    private func tick() {
        for (key, subscriber) in subscribers {
            guard let value = subscriber.value else {
                subscribers.removeValue(forKey: key)
                continue
            }
            value.healthCheck()
        }
        stopIfIdle()
    }

    /// 没有订阅者时停掉定时器。
    private func stopIfIdle() {
        guard subscribers.isEmpty else { return }
        timer?.invalidate()
        timer = nil
    }
}
