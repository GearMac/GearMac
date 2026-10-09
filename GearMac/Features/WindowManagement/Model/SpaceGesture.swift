// 文件职责：把切换 Space 的合成 Dock 滑动手势描述为可序列化的字段与 IOHID 数据（纯数据，不发事件）。
// 分层：Model；保持纯净，故意不 import CoreGraphics（用原始字段号替代），仅依赖 Foundation。
import Foundation

/// 切换命令移动到相邻的哪个 Space。
enum SpaceDirection: Sendable {
    case previous
    case next

    init?(_ command: WindowCommand.ID) {
        switch command {
        case .previousSpace: self = .previous
        case .nextSpace: self = .next
        default: return nil
        }
    }

    var reversed: SpaceDirection {
        self == .next ? .previous : .next
    }
}

/// macOS 用来切换 Space 的合成 Dock 滑动手势，以数据而非事件的形式表示。
enum SpaceGesture {
    /// Dock 会忽略跳过任一拍的手势，因此三个阶段总是一起发出。
    enum Phase: Int64, CaseIterable, Sendable {
        case began = 1
        case changed = 2
        case ended = 4
    }

    enum FieldValue: Equatable, Sendable {
        case integer(Int64)
        case double(Double)
    }

    /// 一次 `CGEvent` 字段写入，以原始编号为键，使本文件无需 CoreGraphics。
    struct Field: Equatable, Sendable {
        let raw: UInt32
        let value: FieldValue
    }

    /// 是动量而非速度：2000 会多冲过两个 Space，降低它不会增加延迟。
    static let velocity = 1000.0

    /// macOS 27 会把紧挨着发出的阶段合并，结果变成一次双倍移动。
    static let phaseDelay = Duration.milliseconds(10)

    /// `CGEventCreateData` 输出的序列化版本；拼接逻辑只认识这个布局。
    static let dataVersion: [UInt8] = [0, 0, 0, 2]

    // MARK: - Fields

    /// 某个阶段的 gesture 字段。`augmented` 选择 macOS 27 的编码。
    static func fields(
        phase: Phase, direction: SpaceDirection, augmented: Bool, timestamp: UInt64
    ) -> [Field] {
        let sign = direction == .next ? 1.0 : -1.0
        var fields = [
            Field(raw: eventTypeField, value: .integer(dockControlEventType)),
            Field(raw: hidTypeField, value: .integer(dockSwipeHIDType)),
            Field(raw: phaseField, value: .integer(phase.rawValue)),
            Field(raw: progressField, value: .double(sign * progressMagnitude(augmented))),
            Field(raw: motionField, value: .integer(horizontalMotion))
        ]

        guard augmented else {
            fields.append(Field(raw: velocityXField, value: .double(sign * velocity)))
            fields.append(Field(raw: velocityYField, value: .double(sign * velocity)))
            return fields
        }

        fields.append(Field(raw: phaseAliasField, value: .integer(phase.rawValue)))
        fields.append(Field(raw: zoomDeltaYField, value: .double(zoomDeltaY)))
        fields.append(Field(raw: processAliasField, value: .double(Double(timestamp))))
        fields.append(Field(raw: positionXField, value: .double(positionX)))
        // 在非最后阶段给速度会让 Space 在稳定前又滑回去。
        if phase == .ended {
            fields.append(Field(raw: velocityXField, value: .double(sign * velocity)))
        }
        return fields
    }

    // MARK: - IOHID payload

    /// `CGEventCreateData` 为字段加框的记录头：大端 size，随后 tag 与 id。
    static func payloadRecordHeader(payloadCount: Int) -> [UInt8] {
        [
            UInt8(truncatingIfNeeded: payloadCount >> 8), UInt8(truncatingIfNeeded: payloadCount),
            UInt8(truncatingIfNeeded: payloadField >> 8), UInt8(truncatingIfNeeded: payloadField)
        ]
    }

    /// macOS 27 用来校验该手势的 IOHID 队列元素，对应 `payloadField`。
    static func payload(phase: Phase, direction: SpaceDirection, timestamp: UInt64) -> Data {
        let sign = direction == .next ? 1.0 : -1.0
        let carriesVelocity = phase == .ended

        var payload = queueHeader(
            timestamp: timestamp, eventCount: carriesVelocity ? 2 : 1)
        payload.append(fluidRecord(phase: phase, progress: sign * progressMagnitude(true)))
        guard carriesVelocity else { return payload }
        payload.append(velocityRecord(x: sign * velocity))
        return payload
    }

    /// 16.16 定点数，太小而无法编码的值向下取到 ±1，因此绝不会落到零。
    static func fixed1616(_ value: Double) -> Int32 {
        let fixed = Int32(value * 65536)
        if fixed == 0, value != 0 { return value > 0 ? 1 : -1 }
        return fixed
    }

    /// `IOHIDSystemQueueElementHeader`：时间戳、发送者 id、options、属性长度、数量。
    private static func queueHeader(timestamp: UInt64, eventCount: UInt32) -> Data {
        var header = Data()
        header.append(littleEndian: timestamp)
        header.append(littleEndian: UInt64(0))
        header.append(littleEndian: UInt32(0))
        header.append(littleEndian: UInt32(0))
        header.append(littleEndian: eventCount)
        return header
    }

    /// `IOHIDFluidTouchGestureData`：position x/y/z、swipe mask、motion、flavour、progress。
    private static func fluidRecord(phase: Phase, progress: Double) -> Data {
        var record = eventBase(
            size: fluidRecordSize, type: fluidTouchGestureType,
            options: UInt32(truncatingIfNeeded: phase.rawValue & 0xFF) << 24, depth: 0)
        record.append(littleEndian: fixed1616(positionX))
        record.append(littleEndian: Int32(0))
        record.append(littleEndian: Int32(0))
        record.append(littleEndian: UInt32(0))
        record.append(littleEndian: UInt16(truncatingIfNeeded: horizontalMotion))
        record.append(littleEndian: dockPrimaryFlavor)
        record.append(littleEndian: fixed1616(progress))
        return record
    }

    /// `IOHIDVelocityEventData`：velocity x/y/z。
    private static func velocityRecord(x: Double) -> Data {
        var record = eventBase(size: velocityRecordSize, type: velocityType, options: 0, depth: 1)
        record.append(littleEndian: fixed1616(x))
        record.append(littleEndian: Int32(0))
        record.append(littleEndian: Int32(0))
        return record
    }

    /// `IOHIDEventBase`：size、type、options、depth，随后三个保留字节。
    private static func eventBase(
        size: UInt32, type: UInt32, options: UInt32, depth: UInt8
    ) -> Data {
        var base = Data()
        base.append(littleEndian: size)
        base.append(littleEndian: type)
        base.append(littleEndian: options)
        base.append(littleEndian: depth)
        base.append(contentsOf: [0, 0, 0])
        return base
    }

    /// `leastNonzeroMagnitude` 能通过旧版路径，但在 16.16 中会截断为零。
    private static func progressMagnitude(_ augmented: Bool) -> Double {
        augmented ? 0.000016 : Double(Float.leastNonzeroMagnitude)
    }

    // MARK: - Undocumented constants

    static let payloadField: UInt32 = 4205

    private static let eventTypeField: UInt32 = 55
    private static let hidTypeField: UInt32 = 110
    private static let motionField: UInt32 = 123
    private static let progressField: UInt32 = 124
    private static let positionXField: UInt32 = 125
    private static let velocityXField: UInt32 = 129
    private static let velocityYField: UInt32 = 130
    private static let phaseField: UInt32 = 132
    private static let phaseAliasField: UInt32 = 134
    private static let zoomDeltaYField: UInt32 = 138
    private static let processAliasField: UInt32 = 169

    private static let dockControlEventType: Int64 = 30
    private static let dockSwipeHIDType: Int64 = 23
    private static let horizontalMotion: Int64 = 1

    private static let fluidRecordSize: UInt32 = 40
    private static let velocityRecordSize: UInt32 = 28
    private static let fluidTouchGestureType: UInt32 = 23
    private static let velocityType: UInt32 = 9
    private static let dockPrimaryFlavor: UInt16 = 3

    private static let positionX = 0.1
    private static let zoomDeltaY = 3.0
}

extension Data {
    /// IOHID 队列是紧凑的小端布局，因此每个标量都以原始字节写入。
    fileprivate mutating func append<T: FixedWidthInteger>(littleEndian value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
