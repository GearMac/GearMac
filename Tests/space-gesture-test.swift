// 文件职责：Space 切换手势表与 IOHID 上报字节的独立契约测试 harness，校验方向映射、16.16 定点编码、字段表与事件负载布局。
// 分层：测试 harness；仅 import Foundation，不依赖 AppKit，通过进程退出码报告失败。
import Foundation

@main
@MainActor
struct SpaceGestureTests {
    static var failures = 0
    static var passes = 0

    /// 断言辅助：条件为假时累加失败计数并打印消息。
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    /// 断言辅助：条件为假时累加失败计数并打印消息。
    static func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        if actual == expected {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message) — got \(actual), expected \(expected)")
        }
    }

    // MARK: - Fixtures

    /// 从负载字节中读取小端序整数。
    /// 负载按 little-endian 打包，因此每次读取都复刻 WindowServer 的解析方式。
    static func read<T: FixedWidthInteger>(_ data: Data, at offset: Int, as type: T.Type) -> T {
        let start = data.startIndex + offset
        return data[start..<start + MemoryLayout<T>.size]
            .reversed()
            .reduce(T(0)) { $0 << 8 | T($1) }
    }

    /// 以固定时间戳构造指定阶段/方向/是否 augmented 的字段表。
    static func fields(
        _ phase: SpaceGesture.Phase, _ direction: SpaceDirection, augmented: Bool
    ) -> [SpaceGesture.Field] {
        SpaceGesture.fields(
            phase: phase, direction: direction, augmented: augmented, timestamp: 12_345)
    }

    /// 取指定 raw 字段的值，不存在时返回 nil。
    static func value(_ fields: [SpaceGesture.Field], _ raw: UInt32) -> SpaceGesture.FieldValue? {
        fields.first { $0.raw == raw }?.value
    }

    /// 取指定字段的 double 值，字段缺失或类型不符时返回 nil。
    static func double(_ fields: [SpaceGesture.Field], _ raw: UInt32) -> Double? {
        guard case .double(let value) = value(fields, raw) else { return nil }
        return value
    }

    /// 取指定字段的整数值，字段缺失或类型不符时返回 nil。
    static func integer(_ fields: [SpaceGesture.Field], _ raw: UInt32) -> Int64? {
        guard case .integer(let value) = value(fields, raw) else { return nil }
        return value
    }

    /// 依次运行全部用例，并按失败数决定退出码。
    static func main() {
        testDirection()
        testFixedPoint()
        testCommonFields()
        testLegacyFields()
        testAugmentedFields()
        testPayloadShape()
        testPayloadValues()
        testRecordHeader()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Direction

    /// 验证只有 next-space 与 previous-space 两个命令会被识别为方向，且可互相反转。
    static func testDirection() {
        expect(SpaceDirection(.nextSpace) == .next, "next-space maps to the next direction")
        expect(SpaceDirection(.previousSpace) == .previous, "previous-space maps to previous")
        expect(SpaceDirection(.leftHalf) == nil, "a geometry command is not a direction")
        expect(SpaceDirection(.toggleFullscreen) == nil, "fullscreen is not a direction")
        expect(
            WindowCommand.ID.allCases.filter { SpaceDirection($0) != nil }.count == 2,
            "exactly two commands are space switches")
        expect(SpaceDirection.next.reversed == .previous, "next reverses to previous")
        expect(SpaceDirection.previous.reversed == .next, "previous reverses to next")
    }

    // MARK: - Fixed point

    /// 验证 16.16 定点编码的取整与向下取整规则，包括极小值不会退化为零。
    static func testFixedPoint() {
        expectEqual(SpaceGesture.fixed1616(0), 0, "zero encodes as zero")
        expectEqual(SpaceGesture.fixed1616(1), 65_536, "one encodes as one whole unit")
        expectEqual(SpaceGesture.fixed1616(-1), -65_536, "negatives encode symmetrically")
        expectEqual(SpaceGesture.fixed1616(0.5), 32_768, "a half encodes as half a unit")
        expectEqual(SpaceGesture.fixed1616(1000), 65_536_000, "the gesture velocity fits in 16.16")
        // 向下取整（floor）能避免刻意设置的极小进度被量化成空操作。
        expectEqual(SpaceGesture.fixed1616(1e-9), 1, "a value below the step floors to +1")
        expectEqual(SpaceGesture.fixed1616(-1e-9), -1, "a negative value below the step floors to -1")
        expectEqual(
            SpaceGesture.fixed1616(Double(Float.leastNonzeroMagnitude)), 1,
            "the legacy progress magnitude survives as +1 rather than vanishing")
    }

    // MARK: - Fields

    /// 验证两种路径共有的字段表：事件类型、HID 类型、阶段与水平运动，且无重复字段。
    static func testCommonFields() {
        for augmented in [false, true] {
            for phase in SpaceGesture.Phase.allCases {
                let table = fields(phase, .next, augmented: augmented)
                expectEqual(integer(table, 55), 30, "the event is a DockControl event")
                expectEqual(integer(table, 110), 23, "the HID type is a dock swipe")
                expectEqual(integer(table, 132), phase.rawValue, "the phase is carried verbatim")
                expectEqual(integer(table, 123), 1, "the motion is horizontal")
                expect(
                    Set(table.map(\.raw)).count == table.count,
                    "no field is written twice for \(phase) augmented=\(augmented)")
            }
        }
        expectEqual(
            SpaceGesture.Phase.allCases.map(\.rawValue), [1, 2, 4],
            "began, changed and ended are posted in order")
    }

    /// 验证 legacy 路径的进度、速度符号与不写入阶段别名等约定。
    static func testLegacyFields() {
        for phase in SpaceGesture.Phase.allCases {
            let next = fields(phase, .next, augmented: false)
            let previous = fields(phase, .previous, augmented: false)
            expectEqual(
                double(next, 124), Double(Float.leastNonzeroMagnitude),
                "legacy progress is the smallest float, positive for next")
            expectEqual(
                double(previous, 124), -Double(Float.leastNonzeroMagnitude),
                "legacy progress is negative for previous")
            expectEqual(double(next, 129), 1000, "legacy velocity rides on every phase")
            expectEqual(double(next, 130), 1000, "legacy carries velocity on both axes")
            expectEqual(double(previous, 129), -1000, "legacy velocity is signed by direction")
            expect(value(next, 4205) == nil, "the payload is never written as an ordinary field")
        }
        expect(
            fields(.began, .next, augmented: false).allSatisfy { $0.raw != 134 },
            "the legacy path writes no phase alias")
    }

    /// 验证 augmented 路径的阶段别名、缩放增量、时间戳与仅在 ended 阶段携带速度的规则。
    static func testAugmentedFields() {
        for phase in SpaceGesture.Phase.allCases {
            let next = fields(phase, .next, augmented: true)
            let previous = fields(phase, .previous, augmented: true)
            expectEqual(integer(next, 134), phase.rawValue, "the phase alias mirrors the phase")
            expectEqual(double(next, 138), 3, "the zoom delta is the constant the Dock expects")
            expectEqual(double(next, 125), 0.1, "the swipe starts at a nonzero position")
            expectEqual(double(next, 169), 12_345, "the process alias carries the timestamp")
            // 符号与 legacy 路径保持一致；若取反会使 Space 切换方向相反。
            expect(double(next, 124)! > 0, "augmented progress is positive for next")
            expect(double(previous, 124)! < 0, "augmented progress is negative for previous")
            expectEqual(
                SpaceGesture.fixed1616(double(next, 124)!), 1,
                "augmented progress survives 16.16 quantization as exactly one step")
            expect(value(next, 130) == nil, "the augmented path writes no Y velocity")
        }
        expect(
            value(fields(.began, .next, augmented: true), 129) == nil,
            "velocity before the last phase would bounce the Space back")
        expect(
            value(fields(.changed, .next, augmented: true), 129) == nil,
            "the changed phase carries no velocity either")
        expectEqual(
            double(fields(.ended, .next, augmented: true), 129), 1000,
            "only the ended phase flings")
        expectEqual(
            double(fields(.ended, .previous, augmented: true), 129), -1000,
            "the fling is signed by direction")
    }

    // MARK: - Payload

    /// 验证负载长度与事件计数头部（fluid 记录与 ended 阶段追加的速度记录）。
    static func testPayloadShape() {
        for phase in [SpaceGesture.Phase.began, .changed] {
            let payload = SpaceGesture.payload(phase: phase, direction: .next, timestamp: 7)
            expectEqual(payload.count, 68, "a \(phase) payload is a header plus a fluid record")
            expectEqual(read(payload, at: 24, as: UInt32.self), 1, "\(phase) reports one event")
        }
        let ended = SpaceGesture.payload(phase: .ended, direction: .next, timestamp: 7)
        expectEqual(ended.count, 96, "the ended payload appends a velocity record")
        expectEqual(read(ended, at: 24, as: UInt32.self), 2, "the ended payload reports two events")
    }

    /// 验证负载头部与各记录的字段值，包括 16.16 进度/速度与方向符号。
    static func testPayloadValues() {
        let payload = SpaceGesture.payload(phase: .ended, direction: .next, timestamp: 99)
        expectEqual(read(payload, at: 0, as: UInt64.self), 99, "the header carries the timestamp")
        expectEqual(read(payload, at: 8, as: UInt64.self), 0, "the sender id is unset")
        expectEqual(read(payload, at: 20, as: UInt32.self), 0, "there are no trailing attributes")

        expectEqual(read(payload, at: 28, as: UInt32.self), 40, "the fluid record declares its size")
        expectEqual(read(payload, at: 32, as: UInt32.self), 23, "the fluid record is a touch gesture")
        expectEqual(
            read(payload, at: 36, as: UInt32.self), UInt32(SpaceGesture.Phase.ended.rawValue) << 24,
            "the phase rides in the top byte of the record options")
        expectEqual(read(payload, at: 40, as: UInt8.self), 0, "the fluid record sits at depth zero")
        expectEqual(read(payload, at: 44, as: Int32.self), 6_553, "the start position is 0.1 in 16.16")
        expectEqual(read(payload, at: 56, as: UInt32.self), 0, "no swipe mask is claimed")
        expectEqual(read(payload, at: 60, as: UInt16.self), 1, "the record motion is horizontal")
        expectEqual(read(payload, at: 62, as: UInt16.self), 3, "the flavour is the primary dock swipe")
        expectEqual(read(payload, at: 64, as: Int32.self), 1, "progress lands on a single step")

        expectEqual(read(payload, at: 68, as: UInt32.self), 28, "the velocity record declares its size")
        expectEqual(read(payload, at: 72, as: UInt32.self), 9, "the velocity record is a velocity")
        expectEqual(read(payload, at: 80, as: UInt8.self), 1, "the velocity record sits at depth one")
        expectEqual(
            read(payload, at: 84, as: Int32.self), 1000 * 65_536, "the fling velocity is in 16.16")
        expectEqual(read(payload, at: 88, as: Int32.self), 0, "the fling has no vertical component")

        let previous = SpaceGesture.payload(phase: .ended, direction: .previous, timestamp: 99)
        expectEqual(read(previous, at: 64, as: Int32.self), -1, "previous reverses progress")
        expectEqual(
            read(previous, at: 84, as: Int32.self), -1000 * 65_536, "previous reverses the fling")
    }

    /// 验证 IOHID 负载的 big-endian 帧头、字段号与序列化版本。
    static func testRecordHeader() {
        expectEqual(
            SpaceGesture.payloadRecordHeader(payloadCount: 68), [0, 68, 0x10, 0x6D],
            "a 68-byte blob is framed big-endian against field 4205")
        expectEqual(
            SpaceGesture.payloadRecordHeader(payloadCount: 96), [0, 96, 0x10, 0x6D],
            "the framed size tracks the payload")
        expectEqual(
            SpaceGesture.payloadRecordHeader(payloadCount: 300), [1, 44, 0x10, 0x6D],
            "a size past one byte splits across the big-endian pair")
        expectEqual(SpaceGesture.payloadField, 4205, "the payload rides in the raw IOHID field")
        expectEqual(SpaceGesture.dataVersion, [0, 0, 0, 2], "only serialization version 2 is spliced")
    }
}
