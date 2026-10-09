// 文件职责：计算器功能的本地化键与中英词表。
// 分层：Model（本地化）；自包含，不引用其他功能的键。
import Foundation

/// 计算器卡片、历史、设置与错误提示文案的键。
///
/// 引擎产出的徽章与错误文字按 `AppLanguage` 解析，默认英文，因此引擎自身的
/// 纯英文行为（以及依赖它的测试）保持不变。
enum CalculatorKey: String, LocalizableKey {
    // MARK: - 徽章

    case badgeExpression = "calculator.badge.expression"
    case badgeResult = "calculator.badge.result"
    case badgeBoolean = "calculator.badge.boolean"
    case badgeTimespan = "calculator.badge.timespan"
    case badgeDate = "calculator.badge.date"
    case badgeUnixSeconds = "calculator.badge.unixSeconds"
    case badgeUnixMilliseconds = "calculator.badge.unixMilliseconds"

    // MARK: - 百分比与聚合目标

    case targetDiscounted = "calculator.target.discounted"
    case targetPercentage = "calculator.target.percentage"
    case targetTip = "calculator.target.tip"
    case targetTotal = "calculator.target.total"
    case targetRatio = "calculator.target.ratio"
    case targetRounded = "calculator.target.rounded"
    case aggregateAverage = "calculator.target.average"
    case aggregateSum = "calculator.target.sum"
    case aggregateMinimum = "calculator.target.minimum"
    case aggregateMaximum = "calculator.target.maximum"

    // MARK: - 进制

    case baseBinary = "calculator.base.binary"
    case baseOctal = "calculator.base.octal"
    case baseDecimal = "calculator.base.decimal"
    case baseHexadecimal = "calculator.base.hexadecimal"

    // MARK: - 量纲分类

    case categoryLength = "calculator.category.length"
    case categoryWeight = "calculator.category.weight"
    case categoryTemperature = "calculator.category.temperature"
    case categoryTime = "calculator.category.time"
    case categoryArea = "calculator.category.area"
    case categoryVolume = "calculator.category.volume"
    case categoryDigitalStorage = "calculator.category.digitalStorage"
    case categoryAngle = "calculator.category.angle"
    case categorySpeed = "calculator.category.speed"
    case categoryPressure = "calculator.category.pressure"
    case categoryDataRate = "calculator.category.dataRate"
    case categoryAcceleration = "calculator.category.acceleration"
    case categoryForce = "calculator.category.force"
    case categoryEnergy = "calculator.category.energy"
    case categoryPower = "calculator.category.power"
    case categoryFrequency = "calculator.category.frequency"
    case categoryElectricCurrent = "calculator.category.electricCurrent"
    case categoryVoltage = "calculator.category.voltage"
    case categoryResistance = "calculator.category.resistance"
    case categoryElectricCharge = "calculator.category.electricCharge"
    case categoryVolumeFlow = "calculator.category.volumeFlow"
    case categoryCompound = "calculator.category.compound"
    case categoryPixels = "calculator.category.pixels"
    case categoryPixelArea = "calculator.category.pixelArea"
    case categoryPixelDensity = "calculator.category.pixelDensity"
    case categoryCurrency = "calculator.category.currency"

    // MARK: - 错误提示

    case errorCannotConvert = "calculator.error.cannotConvert"
    case errorCannotAdd = "calculator.error.cannotAdd"
    case errorCannotSubtract = "calculator.error.cannotSubtract"
    case errorTemperatureUnits = "calculator.error.temperatureUnits"
    case errorUnitMultiplication = "calculator.error.unitMultiplication"
    case errorTemperatureDivision = "calculator.error.temperatureDivision"
    case errorCompareDimensions = "calculator.error.compareDimensions"
    case errorRatesUnavailable = "calculator.error.ratesUnavailable"
    case errorNoRate = "calculator.error.noRate"

    // MARK: - 展示文本中的单位词

    case timespanWeek = "calculator.timespan.week"
    case timespanDay = "calculator.timespan.day"
    case timespanHour = "calculator.timespan.hour"
    case timespanMinute = "calculator.timespan.minute"
    case timespanSecond = "calculator.timespan.second"
    case footSingular = "calculator.length.foot"
    case footPlural = "calculator.length.feet"
    case inchSingular = "calculator.length.inch"
    case inchPlural = "calculator.length.inches"
    case durationSecond = "calculator.duration.second"
    case durationSeconds = "calculator.duration.seconds"
    case durationMinute = "calculator.duration.minute"
    case durationMinutes = "calculator.duration.minutes"
    case durationHour = "calculator.duration.hour"
    case durationHours = "calculator.duration.hours"
    case durationDay = "calculator.duration.day"
    case durationDays = "calculator.duration.days"
    case durationWeek = "calculator.duration.week"
    case durationWeeks = "calculator.duration.weeks"
    case dayNoteTomorrow = "calculator.dayNote.tomorrow"
    case dayNoteYesterday = "calculator.dayNote.yesterday"
    case dayNoteDaysAgo = "calculator.dayNote.daysAgo"
    case dayNoteInDays = "calculator.dayNote.inDays"

    // MARK: - 卡片与历史动作

    case copyAnswer = "calculator.action.copyAnswer"
    case putAnswerInSearchBar = "calculator.action.putAnswerInSearchBar"
    case copyCalculation = "calculator.action.copyCalculation"
    case copyExpression = "calculator.action.copyExpression"
    case deleteEntry = "calculator.action.deleteEntry"
    case deleteAllEntries = "calculator.action.deleteAllEntries"
    case sectionCalculator = "calculator.section.title"
    case emptyNoCalculations = "calculator.empty.none"
    case emptyNoMatches = "calculator.empty.noMatches"
    case clearHistoryTitle = "calculator.clear.title"
    case clearHistoryMessage = "calculator.clear.message"
    case clearHistoryConfirm = "calculator.clear.confirm"

    // MARK: - 数字格式（设置页展示）

    case numberStyleSystem = "calculator.numberStyle.system"
    case numberStyleEnglish = "calculator.numberStyle.english"

    static let table: [String: L10nEntry] = [
        CalculatorKey.badgeExpression.rawValue: L10nEntry("Expression", "表达式"),
        CalculatorKey.badgeResult.rawValue: L10nEntry("Result", "结果"),
        CalculatorKey.badgeBoolean.rawValue: L10nEntry("Boolean", "布尔值"),
        CalculatorKey.badgeTimespan.rawValue: L10nEntry("Timespan", "时长"),
        CalculatorKey.badgeDate.rawValue: L10nEntry("Date", "日期"),
        CalculatorKey.badgeUnixSeconds.rawValue: L10nEntry("Unix Seconds", "Unix 秒"),
        CalculatorKey.badgeUnixMilliseconds.rawValue: L10nEntry("Unix Milliseconds", "Unix 毫秒"),

        CalculatorKey.targetDiscounted.rawValue: L10nEntry("Discounted", "折后价"),
        CalculatorKey.targetPercentage.rawValue: L10nEntry("Percentage", "百分比"),
        CalculatorKey.targetTip.rawValue: L10nEntry("Tip", "小费"),
        CalculatorKey.targetTotal.rawValue: L10nEntry("Total", "总数"),
        CalculatorKey.targetRatio.rawValue: L10nEntry("Ratio", "比值"),
        CalculatorKey.targetRounded.rawValue: L10nEntry("Rounded", "取整"),
        CalculatorKey.aggregateAverage.rawValue: L10nEntry("Average", "平均值"),
        CalculatorKey.aggregateSum.rawValue: L10nEntry("Sum", "合计"),
        CalculatorKey.aggregateMinimum.rawValue: L10nEntry("Minimum", "最小值"),
        CalculatorKey.aggregateMaximum.rawValue: L10nEntry("Maximum", "最大值"),

        CalculatorKey.baseBinary.rawValue: L10nEntry("Binary", "二进制"),
        CalculatorKey.baseOctal.rawValue: L10nEntry("Octal", "八进制"),
        CalculatorKey.baseDecimal.rawValue: L10nEntry("Decimal", "十进制"),
        CalculatorKey.baseHexadecimal.rawValue: L10nEntry("Hexadecimal", "十六进制"),

        CalculatorKey.categoryLength.rawValue: L10nEntry("Length", "长度"),
        CalculatorKey.categoryWeight.rawValue: L10nEntry("Weight", "重量"),
        CalculatorKey.categoryTemperature.rawValue: L10nEntry("Temperature", "温度"),
        CalculatorKey.categoryTime.rawValue: L10nEntry("Time", "时间"),
        CalculatorKey.categoryArea.rawValue: L10nEntry("Area", "面积"),
        CalculatorKey.categoryVolume.rawValue: L10nEntry("Volume", "体积"),
        CalculatorKey.categoryDigitalStorage.rawValue: L10nEntry("Digital Storage", "数字存储"),
        CalculatorKey.categoryAngle.rawValue: L10nEntry("Angle", "角度"),
        CalculatorKey.categorySpeed.rawValue: L10nEntry("Speed", "速度"),
        CalculatorKey.categoryPressure.rawValue: L10nEntry("Pressure", "压强"),
        CalculatorKey.categoryDataRate.rawValue: L10nEntry("Data Transfer Rate", "数据传输速率"),
        CalculatorKey.categoryAcceleration.rawValue: L10nEntry("Acceleration", "加速度"),
        CalculatorKey.categoryForce.rawValue: L10nEntry("Force", "力"),
        CalculatorKey.categoryEnergy.rawValue: L10nEntry("Energy", "能量"),
        CalculatorKey.categoryPower.rawValue: L10nEntry("Power", "功率"),
        CalculatorKey.categoryFrequency.rawValue: L10nEntry("Frequency", "频率"),
        CalculatorKey.categoryElectricCurrent.rawValue: L10nEntry("Electric Current", "电流"),
        CalculatorKey.categoryVoltage.rawValue: L10nEntry("Voltage", "电压"),
        CalculatorKey.categoryResistance.rawValue: L10nEntry("Resistance", "电阻"),
        CalculatorKey.categoryElectricCharge.rawValue: L10nEntry("Electric Charge", "电荷"),
        CalculatorKey.categoryVolumeFlow.rawValue: L10nEntry("Volume Flow Rate", "体积流量"),
        CalculatorKey.categoryCompound.rawValue: L10nEntry("Compound Units", "复合单位"),
        CalculatorKey.categoryPixels.rawValue: L10nEntry("Pixels", "像素"),
        CalculatorKey.categoryPixelArea.rawValue: L10nEntry("Pixel Area", "像素面积"),
        CalculatorKey.categoryPixelDensity.rawValue: L10nEntry("Pixel Density", "像素密度"),
        CalculatorKey.categoryCurrency.rawValue: L10nEntry("Currency", "货币"),

        CalculatorKey.errorCannotConvert.rawValue: L10nEntry(
            "Cannot convert %@ to %@.", "无法将 %@ 转换为 %@。"),
        CalculatorKey.errorCannotAdd.rawValue: L10nEntry("Cannot add %@ and %@.", "无法将 %@ 与 %@ 相加。"),
        CalculatorKey.errorCannotSubtract.rawValue: L10nEntry(
            "Cannot subtract %@ and %@.", "无法将 %@ 与 %@ 相减。"),
        CalculatorKey.errorTemperatureUnits.rawValue: L10nEntry(
            "Cannot combine temperatures with different units.", "无法组合单位不同的温度。"),
        CalculatorKey.errorUnitMultiplication.rawValue: L10nEntry(
            "Multiplication of these unit values is not supported.", "不支持这些单位值相乘。"),
        CalculatorKey.errorTemperatureDivision.rawValue: L10nEntry(
            "Division of temperature values is not supported.", "不支持温度值相除。"),
        CalculatorKey.errorCompareDimensions.rawValue: L10nEntry(
            "Cannot compare values with different dimensions.", "无法比较量纲不同的值。"),
        CalculatorKey.errorRatesUnavailable.rawValue: L10nEntry(
            "Exchange rates unavailable — check your connection.", "汇率不可用——请检查网络连接。"),
        CalculatorKey.errorNoRate.rawValue: L10nEntry("No exchange rate for %@.", "没有 %@ 的汇率。"),

        CalculatorKey.timespanWeek.rawValue: L10nEntry("wk", "周"),
        CalculatorKey.timespanDay.rawValue: L10nEntry("day", "天"),
        CalculatorKey.timespanHour.rawValue: L10nEntry("hr", "小时"),
        CalculatorKey.timespanMinute.rawValue: L10nEntry("min", "分钟"),
        CalculatorKey.timespanSecond.rawValue: L10nEntry("s", "秒"),
        CalculatorKey.footSingular.rawValue: L10nEntry("foot", "英尺"),
        CalculatorKey.footPlural.rawValue: L10nEntry("feet", "英尺"),
        CalculatorKey.inchSingular.rawValue: L10nEntry("inch", "英寸"),
        CalculatorKey.inchPlural.rawValue: L10nEntry("inches", "英寸"),
        CalculatorKey.durationSecond.rawValue: L10nEntry("second", "秒"),
        CalculatorKey.durationSeconds.rawValue: L10nEntry("seconds", "秒"),
        CalculatorKey.durationMinute.rawValue: L10nEntry("minute", "分钟"),
        CalculatorKey.durationMinutes.rawValue: L10nEntry("minutes", "分钟"),
        CalculatorKey.durationHour.rawValue: L10nEntry("hour", "小时"),
        CalculatorKey.durationHours.rawValue: L10nEntry("hours", "小时"),
        CalculatorKey.durationDay.rawValue: L10nEntry("day", "天"),
        CalculatorKey.durationDays.rawValue: L10nEntry("days", "天"),
        CalculatorKey.durationWeek.rawValue: L10nEntry("week", "周"),
        CalculatorKey.durationWeeks.rawValue: L10nEntry("weeks", "周"),
        CalculatorKey.dayNoteTomorrow.rawValue: L10nEntry(" (tomorrow)", "（明天）"),
        CalculatorKey.dayNoteYesterday.rawValue: L10nEntry(" (yesterday)", "（昨天）"),
        CalculatorKey.dayNoteDaysAgo.rawValue: L10nEntry(" (%d days ago)", "（%d 天前）"),
        CalculatorKey.dayNoteInDays.rawValue: L10nEntry(" (in %d days)", "（%d 天后）"),

        CalculatorKey.copyAnswer.rawValue: L10nEntry("Copy Answer", "复制答案"),
        CalculatorKey.putAnswerInSearchBar.rawValue: L10nEntry(
            "Put Answer in Search Bar", "将答案填入搜索框"),
        CalculatorKey.copyCalculation.rawValue: L10nEntry("Copy Calculation", "复制算式"),
        CalculatorKey.copyExpression.rawValue: L10nEntry("Copy Expression", "复制表达式"),
        CalculatorKey.deleteEntry.rawValue: L10nEntry("Delete Entry", "删除条目"),
        CalculatorKey.deleteAllEntries.rawValue: L10nEntry("Delete All Entries", "删除全部条目"),
        CalculatorKey.sectionCalculator.rawValue: L10nEntry("Calculator", "计算器"),
        CalculatorKey.emptyNoCalculations.rawValue: L10nEntry("No calculations yet", "暂无计算记录"),
        CalculatorKey.emptyNoMatches.rawValue: L10nEntry(
            "No matching calculations", "没有匹配的计算"),
        CalculatorKey.clearHistoryTitle.rawValue: L10nEntry(
            "Clear calculation history?", "清空计算历史？"),
        CalculatorKey.clearHistoryMessage.rawValue: L10nEntry(
            "Every past calculation goes. This can't be undone.", "所有历史计算都会被删除，且无法撤销。"),
        CalculatorKey.clearHistoryConfirm.rawValue: L10nEntry("Clear History", "清空历史"),

        CalculatorKey.numberStyleSystem.rawValue: L10nEntry("System", "跟随系统"),
        CalculatorKey.numberStyleEnglish.rawValue: L10nEntry("English", "English"),
    ]
}
