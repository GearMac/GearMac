// 文件职责：定义计量单位的分类枚举，并给出每类的展示名与物理量纲。
// 分层：Model；纯数据声明，不得 import AppKit/SwiftUI。
import Foundation

/// 计量单位的分类，同时提供面向界面的展示名和对应的物理量纲。
enum UnitCategory: String, CaseIterable, Sendable {
    case length, weight, temperature, time, area, volume, digitalStorage
    case angle, speed, pressure, dataRate, acceleration, force, energy, power, frequency
    case electricCurrent, voltage, resistance, electricCharge, volumeFlow
    case pixels, pixelArea, pixelDensity, compound

    /// 面向界面的分类展示名，按界面语言解析。
    func displayName(_ language: AppLanguage) -> String {
        let key: CalculatorKey =
            switch self {
            case .length: .categoryLength
            case .weight: .categoryWeight
            case .temperature: .categoryTemperature
            case .time: .categoryTime
            case .area: .categoryArea
            case .volume: .categoryVolume
            case .digitalStorage: .categoryDigitalStorage
            case .angle: .categoryAngle
            case .speed: .categorySpeed
            case .pressure: .categoryPressure
            case .dataRate: .categoryDataRate
            case .acceleration: .categoryAcceleration
            case .force: .categoryForce
            case .energy: .categoryEnergy
            case .power: .categoryPower
            case .frequency: .categoryFrequency
            case .electricCurrent: .categoryElectricCurrent
            case .voltage: .categoryVoltage
            case .resistance: .categoryResistance
            case .electricCharge: .categoryElectricCharge
            case .volumeFlow: .categoryVolumeFlow
            case .compound: .categoryCompound
            case .pixels: .categoryPixels
            case .pixelArea: .categoryPixelArea
            case .pixelDensity: .categoryPixelDensity
            }
        return L10n.string(key, language: language)
    }

    /// 该分类对应的物理量纲；温度、角度与复合单位没有单一量纲，返回 nil。
    var dimension: CalcDimension? {
        switch self {
        case .length: return CalcDimension(length: 1)
        case .weight: return CalcDimension(mass: 1)
        case .time: return CalcDimension(time: 1)
        case .area: return CalcDimension(length: 2)
        case .volume: return CalcDimension(length: 3)
        case .digitalStorage: return CalcDimension(data: 1)
        case .speed: return CalcDimension(length: 1, time: -1)
        case .pressure: return CalcDimension(length: -1, mass: 1, time: -2)
        case .dataRate: return CalcDimension(time: -1, data: 1)
        case .acceleration: return CalcDimension(length: 1, time: -2)
        case .force: return CalcDimension(length: 1, mass: 1, time: -2)
        case .energy: return CalcDimension(length: 2, mass: 1, time: -2)
        case .power: return CalcDimension(length: 2, mass: 1, time: -3)
        case .frequency: return CalcDimension(time: -1)
        case .electricCurrent: return CalcDimension(electricCurrent: 1)
        case .voltage: return CalcDimension(length: 2, mass: 1, time: -3, electricCurrent: -1)
        case .resistance: return CalcDimension(length: 2, mass: 1, time: -3, electricCurrent: -2)
        case .electricCharge: return CalcDimension(time: 1, electricCurrent: 1)
        case .volumeFlow: return CalcDimension(length: 3, time: -1)
        case .pixels: return CalcDimension(pixels: 1)
        case .pixelArea: return CalcDimension(pixels: 2)
        case .pixelDensity: return CalcDimension(length: -1, pixels: 1)
        case .temperature, .angle, .compound: return nil
        }
    }
}
