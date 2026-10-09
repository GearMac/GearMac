// 文件职责：计算器引擎的独立测试 harness，编译真实的仅依赖 Foundation 的源码并逐条断言其行为。
// 分层：测试 harness；仅依赖 Foundation 与计算器源码，不 import AppKit/SwiftUI，通过 @main 独立运行。
import Foundation

/// 独立可执行的测试入口：以固定时钟与固定汇率驱动 CalcEngine，逐条断言并统计通过/失败数。
@main
@MainActor
struct CalcTests {
    static var failures = 0
    static var passes = 0

    /// 运行全部断言（算术、单位、日期/时间、区域格式、链式），最后打印统计并按失败数退出。
    static func main() {
        // 算术与优先级
        expectDisplay("2+2", "4")
        expectDisplay("5*7", "35")
        expectDisplay("100/4", "25")
        expectDisplay("2^10", "1,024")
        expectDisplay("2^3^2", "512")  // 右结合
        expectDisplay("2 square root of 9", "6")
        expectDisplay("square root of 25m2", "5 m")
        expectDisplay("cube root of -8m3", "-2 m")
        expectDisplay("cube root of 8%", "0.430886938")
        expectDisplay("cube root of -8%", "-0.430886938")
        expectDisplay("2 * (3 + 4) << 1", "28")
        expectDisplay("1 ≤ 2", "true")
        expectDisplay("2 ≠ 3", "true")
        expectDisplay("2 ⊻ 3", "1")
        expectDisplay("1µs to ns", "1,000 ns")
        expectDisplay("1μs to ns", "1,000 ns")
        expectDisplay("2\u{00A0}+\u{2009}2", "4")
        expectError("10 colo\u{0301}n to usd", "No exchange rate for CRC.")
        expectCopy("-9007199254740992 + 0", "-9007199254740992")
        expectCopy("-0 * 1234", "0")
        expectExpression("10k +", "10k +")
        expectExpression("45+", "45+")
        expectExpression("(2)+", "(2)+")
        expectDisplay("2m / 2m to hex", "0x1")
        expectDisplay(String(repeating: "1+", count: 100) + "1", "101")
        expectNil(String(repeating: "1+", count: 128) + "1")
        expectDisplay("2**2", "4")  // "**" 是 "^" 的别名（Python/JS/shell 写法）
        expectDisplay("2**10", "1,024")
        expectDisplay("2**3**2", "512")  // 右结合，与 "^" 相同
        expectDisplay("(5+2)*3", "21")
        expectDisplay("5!", "120")
        expectDisplay("3!!", "720")  // (3!)! —— 链式后缀
        expectDisplay("-5+3", "-2")
        expectDisplay("-2^2", "-4")  // 一元负号的结合力弱于 ^
        expectDisplay("10/4", "2.5")
        expectDisplay("1/3", "0.3333333333")
        expectDisplay("2.5 * 4", "10")
        expectDisplay("1,000 + 234", "1,234")  // 输入中接受分组逗号

        // 紧凑千位后缀 —— 紧贴的 `k` 是数字后缀；带空格的 `k` 仍是 Kelvin
        expectDisplay("10k", "10,000")
        expectCopy("10k", "10000")
        expectDisplay("2.5K", "2,500")
        expectDisplay("10k + 500", "10,500")
        expectDisplay("10k * 2", "20,000")
        expectBadges("10k", source: "Expression", target: "Result")

        // 量级词会放大其前的字面量，空格分隔或紧贴、任意大小写均可
        expectDisplay("13 million", "13,000,000")
        expectCopy("1.5 billion", "1500000000")
        expectDisplay("2 Thousand + 1", "2,001")
        expectDisplay("3million / 2", "1,500,000")
        expectDisplay("13 million idr to usd", "720.10 USD")
        expectDisplay("1.5 million idr to sgd", "112.17 SGD")
        expectDisplay("IDR 13 million to usd", "720.10 USD")
        expectDisplay("10% of 2 million", "200,000")
        expectExpression("13 million +", "13 million +")
        expectBadges("13 million", source: "Expression", target: "Result")
        expectNil("million")
        expectNil("2 * million")
        expectNil("(2 + 3) million")
        expectNil("13 millions")
        expectNil("13 million2")
        expectNil("1e308 billion")
        expectDisplay("10 milliseconds to s", "0.01 s")
        expectLocalized("1,5 million", "1.500.000", italian)

        // 科学计数法输入
        expectDisplay("1e6 + 1", "1,000,001")
        expectDisplay("1.5e-3 * 2", "0.003")
        expectDisplay("2.5e8 / 2", "125,000,000")
        expectDisplay("1E6 + 1", "1,000,001")  // 大写 E
        expectDisplay("1e6", "1,000,000")  // 单独的简写字面量会像 "10k" 一样出卡片
        expectDisplay("10em", "160 px")  // 不完整的 "e" 不是指数，因此 `em` 仍是单位
        expectDisplay("1e3k + 1", "1,000,001")  // 先指数后紧凑后缀，两者都生效

        // 精确到 2^53，突破旧的 1e15 截断点 —— 此前截断会在复制时丢失真实数字
        expectDisplay("2^49", "562,949,953,421,312")
        expectDisplay("2^50", "1,125,899,906,842,624")
        expectCopy("2^50", "1125899906842624")
        expectDisplay("999999999999999 + 1", "1,000,000,000,000,000")  // 恰好是旧截断点
        // 超过 2^53 后精度确实丢失，因此指数形式才是诚实的答案
        expectDisplay("123456789 * 123456789", "1.524157875e+16")

        // 函数
        expectDisplay("sqrt(64)", "8")
        expectDisplay("sqrt 64", "8")
        expectDisplay("sqrt 64 + 36", "44")  // 裸参数只算一个操作数：sqrt(64) + 36
        expectDisplay("log(1000)", "3")
        expectDisplay("ln(e)", "1")
        expectDisplay("sin(30deg)", "0.5")
        expectDisplay("cos(60deg)", "0.5")
        expectDisplay("tan(45deg)", "1")
        expectDisplay("sin(pi/2)", "1")
        expectDisplay("abs(-4)", "4")
        expectDisplay("floor(2.7)", "2")
        expectDisplay("ceil(2.1)", "3")
        expectDisplay("round(2.5)", "3")
        expectDisplay("SQRT(64)", "8")  // 不区分大小写

        // 常量
        expectDisplay("2*pi", "6.283185307")
        expectDisplay("π*2", "6.283185307")
        expectDisplay("e^2", "7.389056099")

        // 隐式乘法
        expectDisplay("4(2+3)", "20")
        expectDisplay("(2+3)(2+3)", "25")
        expectDisplay("2pi", "6.283185307")
        expectDisplay("2π", "6.283185307")
        expectDisplay("2sqrt(9)", "6")
        expectDisplay("2(3+1)+1", "9")  // 隐式 "*" 与显式 "*" 结合力相同，不会更松
        expectDisplay("10π ^e", "224.5915772")  // 但弱于 "^"
        expectDisplay("3x3", "9")
        expectDisplay("3 x 3", "9")
        expectDisplay("3X3", "9")
        expectDisplay("3 x -2", "-6")
        expectDisplay("2xpi", "6.283185307")
        expectDisplay("6/2x(1+2)", "9")
        expectDisplay("10 x", "10")
        expectDisplay("$5 x 2", "10.00 USD")
        expectNil("x")
        expectNil("x3")
        expectNil("3x")
        // 与括号并列时单位会传递，行为与显式 "*" 一致
        expectDisplay("2(3)kg", "6 kg")
        expectDisplay("2*(3)kg", "6 kg")
        expectDisplay("2(3)kg x 2", "12 kg")

        // 科学计数法 —— 仅当指数紧贴尾数时成立
        expectDisplay("1e5", "100,000")
        expectDisplay("2e10", "20,000,000,000")
        expectDisplay("1E5", "100,000")
        expectDisplay("1.5e3", "1,500")
        expectDisplay("3e+2", "300")
        expectCopy("1e-5", "1e-05")
        expectDisplay("2e10/2", "10,000,000,000")
        expectDisplay("1e5 to hex", "0x186A0")
        expectDisplay("5e-3km", "0.003106855961 mi")
        expectDisplay("2e", "5.436563657")  // "e" 后没有数字 —— 仍是 2 × 欧拉常数 e
        expectDisplay("1 e", "2.718281828")  // 分离 —— 永远不是指数
        expectNil("1e400")  // 溢出为无穷大，因此不算计算器输入
        expectNil("1e308k")
        expectNil("-1e308k")
        expectNil("1e308k to hex")
        expectNil("1e308 * 2 > 1")
        expectNil("1e308m + 1e308m > 0m")
        expectNil("1e308m == 1e308km")
        expectNil("(1e308 * 2) ^ 0")
        expectDisplay("1e305k", "1e+308")
        expectNil("1e5e5")

        // 百分比
        expectDisplay("20% of 450", "90")
        expectDisplay("450 + 20%", "540")
        expectDisplay("450 - 15%", "382.5")
        expectDisplay("20%", "0.2")

        // 取模 —— 以单词拼写，因此不会与上面的百分比用例冲突
        expectDisplay("10 mod 3", "1")
        expectDisplay("17 mod 5", "2")
        expectDisplay("10k mod 3", "1")
        expectDisplay("-10 mod 3", "-1")  // fmod 语义：符号跟随被除数
        expectDisplay("2 + 10 mod 3", "3")  // 与 * 和 / 同优先级，结合力强于 +
        expectNil("10 mod 0")
        expectNil("10 % 3")  // "%" 始终是百分比，无论后面跟什么
        expectDisplay("450 + 20% - 5", "535")

        // 单位换算 —— 长度 / 重量 / 温度 / 时间 / 面积 / 体积 / 存储
        expectDisplay("10km to mi", "6.213711922 mi")
        expectDisplay("10 km in miles", "6.213711922 mi")
        expectDisplay("5ft in cm", "152.4 cm")
        expectDisplay("1 m to ft", "3.280839895 ft")
        expectDisplay("10 cm in in", "3.937007874 in")
        expectDisplay("10 in in cm", "25.4 cm")  // 第一个 "in" 是单位，第二个是连接词
        expectDisplay("16 oz to lb", "1 lb")
        expectDisplay("2.2 lbs to kg", "0.997903214 kg")
        expectDisplay("100 C to F", "212 °F")
        expectDisplay("32F to C", "0 °C")
        expectDisplay("273.15K to C", "0 °C")  // 紧贴的 Kelvin 在换算中依然有效
        expectDisplay("273.15 K to C", "0 °C")
        expectDisplay("10 k to c", "-263.15 °C")
        expectDisplay("0 F to C", "-17.77777778 °C")
        expectDisplay("300 K to C", "26.85 °C")
        expectDisplay("90min to hr", "1.5 hr")
        expectDisplay("2hr to min", "120 min")
        expectDisplay("1day to sec", "86,400 s")
        expectDisplay("1 week to hr", "168 hr")
        expectDisplay("3 months to days", "91.310625 day")
        expectDisplay("3.5 years to days", "1,278.34875 day")
        expectCopy("3.5 years to days", "1278.34875 day")
        expectDisplay("1month in days", "30.436875 day")
        expectDisplay("1mo -> s", "2,629,746 s")
        expectDisplay("1YEAR to s", "31,556,952 s")
        expectDisplay("1yr to months", "12 mo")
        expectDisplay("12 months to years", "1 yr")
        expectDisplay("365.2425 days to year", "1 yr")
        expectDisplay("-0.5 years to months", "-6 mo")
        expectDisplay("0 months to days", "0 day")
        expectDisplay("(1 year + 6 months) to days", "547.86375 day")
        expectBadges("3.5 years to days", source: "Years", target: "Days")
        expectDisplay("2 acre to m2", "8,093.712845 m²")
        expectDisplay("1 m² to ft²", "10.76391042 ft²")
        expectDisplay("2L -> mL", "2,000 mL")
        expectDisplay("1 cup to tbsp", "16 tbsp")
        expectDisplay("1 gal to L", "3.785411784 L")
        expectDisplay("1 GiB to MB", "1,073.741824 MB")
        expectDisplay("1 GB to MiB", "953.6743164 MiB")
        expectDisplay("8 bit to byte", "1 B")
        expectDisplay("2*5 km to mi", "6.213711922 mi")  // 左侧是表达式

        // 进制
        expectBadges("0b1010", source: "Binary", target: "Decimal")
        expectBadges("0o17", source: "Octal", target: "Decimal")
        expectBadges("0B1010 +", source: "Binary", target: "Decimal")
        expectBadges("0O17 +", source: "Octal", target: "Decimal")
        expectCopy("1.00000000004m to pm +", "1000000000040 pm")
        expectCopy("1.00000000004m to pm **", "1000000000040 pm")
        expectCopy("1.00000000004m to pm + =", "1000000000040 pm")
        expectCopy("1.00000000004m to pm + +", "1000000000040 pm")
        expectCopy("1.00000000004 * 1e12 to hex +", "0xE8D4A51028")
        expectDisplay("255 to hex", "0xFF")
        expectDisplay("255 to binary", "0b11111111")
        expectDisplay("0xff to decimal", "255")
        expectDisplay("0b1010 to decimal", "10")
        expectDisplay("255 to octal", "0o377")
        expectDisplay("0xff", "255")  // 裸进制字面量回显为十进制

        // 友好的类别错误
        expectError("10kg to sec", "Cannot convert Weight to Time.")
        expectError("100 mL to km", "Cannot convert Volume to Length.")
        expectError("1 GB to hr", "Cannot convert Digital Storage to Time.")
        expectError("1 year to kg", "Cannot convert Time to Weight.")

        // 非计算器输入 → 不出卡片
        expectNil("safari")
        expectNil("1password")
        expectNil("45")
        expectNil("3.14")
        expectNil("pi")
        expectNil("e")
        expectNil("10km to")  // 只输入了一半的换算
        expectNil("10 to mi")
        expectDisplay("45+", "45")  // 安全的尾部运算符会保留最后一个完整结果
        expectNil("sqrt()")
        expectNil("2.5!")  // 阶乘需要整数
        expectNil("")

        expectDisplay("hypot(3,4)", "5")
        expectDisplay("2hypot(3,4)", "10")
        expectDisplay("round(3.14159,2)", "3.14")
        expectDisplay("round(1234,-2)", "1,200")
        expectDisplay("log(8,2)", "3")
        expectDisplay("gcd(12,18,8)", "2")
        expectDisplay("lcm(4,6)", "12")
        expectDisplay("atan2(1,1)*4", "3.141592654")
        expectDisplay("root(-8,3)", "-2")
        expectDisplay("hypot(3m,400cm)", "5 m")
        expectDisplay("min(1km,999m)", "0.999 km")
        expectDisplay("sum(1km,500m)", "1.5 km")
        expectDisplay("round(2.567km,1)", "2.6 km")
        expectError("min(1km,1hr)", "Cannot compare values with different dimensions.")
        expectNil("gcd(1.5,2)")
        expectNil("lcm(9223372036854775807,2)")
        expectNil("round(1,9999)")
        expectDisplay("1 << 8", "256")
        expectDisplay("256 >> 2", "64")
        expectDisplay("6 & 3", "2")
        expectDisplay("5 xor 3", "6")
        expectDisplay("~1", "-2")
        expectDisplay("1 | 2 == 3", "true")
        expectDisplay("~1 == -2", "true")
        expectDisplay("1km == 1000m", "true")
        expectDisplay("30min >= 1hr", "false")
        expectNil("1 << 64")
        expectNil("1 << -1")
        expectNil("1 << 63")
        expectNil("9007199254740993 & 1")
        expectNil("0x20000000000001 & 1")
        expectDisplay("5 mod 2 == 1", "true")
        expectExpression("1 << 8 == 256", "1 << 8 == 256")
        expectNil("(1 == 1)kg")
        expectNil("-(1 == 1)")
        expectNil("sqrt(1 == 1)")

        // 格式化：display 带分组，copyText 为纯文本
        expectDisplay("1234567*1", "1,234,567")
        expectCopy("1234567*1", "1234567")
        expectCopy("10km to mi", "6.213711922 mi")
        expectDisplay("-1234.5-0.25", "-1,234.75")

        // 卡片表达式回显
        expectExpression("3*3", "3×3")
        expectExpression("10km to mi", "10 km")

        // 显式换算上的徽标
        expectBadges("10km to mi", source: "Kilometers", target: "Miles")
        expectBadges("100 C to F", source: "Celsius", target: "Fahrenheit")

        // 裸单位自动换算（无连接词）
        expectDisplay("1m", "3 feet 3.37007874 inches")
        expectExpression("1m", "1 m")
        expectBadges("1m", source: "Meters", target: "Feet")
        expectDisplay("1hr", "60 min")
        expectBadges("1hr", source: "Hours", target: "Minutes")
        expectDisplay("3 weeks", "21 day")
        expectDisplay("3 days", "72 hr")
        expectDisplay("3 months", "91.310625 day")
        expectDisplay("3.5 years", "1,278.34875 day")
        expectBadges("3 months", source: "Months", target: "Days")
        expectBadges("3.5 years", source: "Years", target: "Days")
        expectDisplay("5ft", "1.524 m")
        expectDisplay("100g", "3.527396195 oz")
        expectDisplay("2*3 kg", "6 kg")  // 有运算符时答案保持所写的单位
        expectDisplay("20 celsius", "68 °F")
        expectDisplay("50cm", "19.68503937 in")
        // 有歧义的单字母别名仍作为应用搜索，而不是裸温度
        expectNil("5 k")
        expectNil("100 c")
        expectNil("32f")

        // 单位表达式 —— 加减法换算右侧操作数并保留最左侧单位
        expectDisplay("10kg + 5kg", "15 kg")
        expectCopy("10kg + 5kg", "15 kg")
        expectExpression("10kg + 5kg", "10 kg + 5 kg")
        // 正负号、括号和后缀 % 紧贴其操作数，而不会作为独立词漂浮
        expectExpression("10kg * 3%", "10 kg × 3%")
        expectExpression("(10kg + 5kg) * 3%", "(10 kg + 5 kg) × 3%")
        expectExpression("-5kg + 2kg", "-5 kg + 2 kg")
        expectExpression("5 feet 3 inches", "5 ft 3 in")
        // 函数保留其括号，单词运算符则把符号留在它引导的操作数上
        expectExpression("hypot(3m,400cm)", "hypot(3 m, 400 cm)")
        expectExpression("min(1km,999m)", "min(1 km, 999 m)")
        expectExpression("round(2.567km,1)", "round(2.567 km, 1)")
        expectExpression("2*sqrt(9)m", "2 × sqrt(9) m")
        expectExpression("cube root of -8m3", "cube root of -8 m³")
        expectExpression("15% of -2kg", "15% of -2 kg")
        expectExpression("10kg - 5kg", "10 kg - 5 kg")
        expectExpression("2 * 5feet 3inches", "2 × 5 ft 3 in")
        expectBadges("10kg + 5kg", source: "Expression", target: "Kilograms")
        expectDisplay("10kg + 10g", "10,010 g")  // issue #64，以最后输入的单位作答
        expectDisplay("10kg + 500g", "10,500 g")
        expectDisplay("500g + 1kg", "1.5 kg")
        expectCopy("500g + 1kg", "1.5 kg")
        expectDisplay("10lb + 5kg", "9.5359237 kg")
        expectDisplay("1m + 50cm", "150 cm")
        expectDisplay("2hr + 30min", "150 min")
        expectDisplay("1GiB + 512MiB", "1,536 MiB")
        expectDisplay("1L - 250mL", "750 mL")
        expectDisplay("-5kg + 2kg", "-3 kg")
        expectDisplay("-(2kg + 500g)", "-2,500 g")
        expectDisplay("10 pounds + 5 pounds", "15 lb")  // 单位在与货币冲突时胜出
        expectDisplay("1m² + 10ft²", "20.76391042 ft²")
        expectDisplay("1L + 1cup", "5.226752838 cup")
        expectDisplay("1GB + 1GiB", "1.931322575 GiB")
        expectDisplay("90deg + 1rad", "2.570796327 rad")
        expectDisplay("60mph + 10kmh", "106.56064 km/h")
        expectDisplay("1bar + 10psi", "24.50377377 psi")
        expectDisplay("1Gbps + 500Mbps", "1,500 Mbps")

        // 单位表达式的优先级、括号、标量运算与约分
        expectDisplay("10kg + 2 * 5kg", "20 kg")
        expectDisplay("(10kg + 5kg) * 2", "30 kg")
        expectDisplay("2 * (3kg + 500g)", "7,000 g")
        expectDisplay("20kg / 2 + 3kg", "13 kg")
        expectDisplay("20kg / (2 + 3)", "4 kg")
        expectDisplay("5kg * 3", "15 kg")
        expectDisplay("10kg / 4", "2.5 kg")
        expectDisplay("5kg / 2kg", "2.5")
        expectBadges("5kg / 2kg", source: "Expression", target: "Result")
        expectDisplay("5kg / 500g", "10")
        expectDisplay("1kg / 3", "0.3333333333 kg")
        expectDisplay("10kg * (2 + 3)", "50 kg")
        expectDisplay("10kg / (2 * 5)", "1 kg")
        expectDisplay("(10kg * 3) / 5kg", "6")
        expectDisplay("10kg / (5kg / 2)", "4")
        expectDisplay("(2kg + 500g) * 4", "10,000 g")
        expectDisplay("(20kg - 5kg) / 3", "5 kg")

        // 百分比在量值运算中贯穿传递
        expectDisplay("10kg + 20%", "12 kg")
        expectDisplay("10kg - 20%", "8 kg")
        expectDisplay("10kg * 20%", "2 kg")
        expectDisplay("10kg * 3%", "0.3 kg")
        expectDisplay("3% * 10kg", "0.3 kg")
        expectDisplay("10kg * 0%", "0 kg")
        expectDisplay("10kg * -3%", "-0.3 kg")
        expectDisplay("10kg / 25%", "40 kg")
        expectDisplay("10kg / 200%", "5 kg")
        expectDisplay("10kg * 3% + 1kg", "1.3 kg")
        expectDisplay("(10kg + 5kg) * 3%", "0.45 kg")
        expectDisplay("10kg * 3% to g", "300 g")
        expectCopy("10kg * 3% to g", "300 g")
        expectDisplay("20% of (10kg + 5kg)", "3 kg")
        expectDisplay("3% of 10kg", "0.3 kg")
        expectNil("10kg / 0%")
        expectDisplay("19m + 47%", "27.93 m")  // Raycast 已记录的行为

        // 不完整表达式保留最后一个完整可用的结果
        expectDisplay("10 +", "10")
        expectDisplay("10 -", "10")
        expectDisplay("10 *", "10")
        expectDisplay("10 /", "10")
        expectDisplay("10 ^", "10")
        expectDisplay("10k +", "10,000")
        expectCopy("10k +", "10000")
        expectDisplay("10kg *", "10 kg")
        expectDisplay("10kg + 500g +", "10,500 g")
        expectDisplay("(10kg + 500g) *", "10,500 g")
        expectDisplay("10kg * 3% +", "0.3 kg")
        expectDisplay("20% of 450 +", "90")
        expectBadges("10 +", source: "Expression", target: "Result")
        expectBadges("10kg *", source: "Expression", target: "Kilograms")
        expectNil("+")
        expectNil("10 + nonsense")
        expectNil("10 + (")
        expectNil("10 of")  // 游离的英文单词是搜索，不是部分表达式

        // 换算后的不完整表达式回显所输入的文本，并保留源进制 / 单位
        expectExpression("10km to mi *", "10km to mi ×")
        expectDisplay("10km to mi *", "6.213711922 mi")
        expectExpression("255 to hex +", "255 to hex +")
        expectBadges("0xff -", source: "Hexadecimal", target: "Decimal")
        expectDisplay("0xff -", "255")

        // 换算后缀作用于整个单位表达式
        expectDisplay("(1kg + 500g) to lb", "3.306933933 lb")
        expectDisplay("10kg + 500g to lb", "23.14853753 lb")
        expectDisplay("(10lb + 5kg) to kg", "9.5359237 kg")
        expectDisplay("(1m + 50cm) to ft", "4.921259843 ft")
        expectBadges("(1kg + 500g) to lb", source: "Expression", target: "Pounds")
        expectError("(1kg + 500g) to m", "Cannot convert Weight to Length.")

        // 复合量按前导单位读作一个量值；有运算符时以最后一个单位作答。
        expectDisplay("5 feet 3 inches to cm", "160.02 cm")
        expectDisplay("5 feet 3 inches", "5.25 ft")
        expectDisplay("1hr 30min", "1.5 hr")
        expectDisplay("5feet + 1m", "2.524 m")
        expectBadges("5feet + 1m", source: "Expression", target: "Meters")
        expectDisplay("1kg + 500g + 2lb", "5.306933933 lb")  // 链式：最后一个单位胜出
        expectDisplay("2 * 5kg", "10 kg")
        expectDisplay("3 * 2m", "6 m")

        // 仿射温度只能在同单位下合并；混用绝对温标存在歧义
        expectDisplay("20 celsius + 10 celsius", "30 °C")
        expectDisplay("68 fahrenheit - 32 fahrenheit", "36 °F")
        expectError(
            "20 celsius + 50 fahrenheit",
            "Cannot combine temperatures with different units.")

        // 明确的量纲错误报错；不完整或非有限输入保持静默
        expectError("1kg + 1m", "Cannot add Weight and Length.")
        expectError("1kg + 1hr", "Cannot add Weight and Time.")
        // 与量值写在一起的裸数字会取它的单位
        expectDisplay("1kg + 1", "2 kg")
        expectDisplay("10kg + 5", "15 kg")
        expectDisplay("5kg+5", "10 kg")
        expectDisplay("5 + 10kg", "15 kg")
        expectDisplay("$10 + 5", "15.00 USD")
        expectBadges("5kg+5", source: "Expression", target: "Kilograms")
        expectDisplay("10kg + -20%", "9.8 kg")  // 一元负号会去掉百分比，与 `450 + -20%` 一致
        // 相邻写法不同：那里的裸数字是仍在输入的单位。
        expectNil("1hr 30")  // 正输入到 "1hr 30min" 的一半
        expectNil("5 feet 3")  // 正输入到 "5 feet 3 inches" 的一半
        expectDisplay("1kg * 1m", "1 kg·m")
        expectDisplay("1cm/m", "0.01")
        expectDisplay("sqrt(4m) to cm^0.5", "20 cm^0.5")
        expectDisplay("1 kg/m3 to g/cm3", "0.001 g/cm³")
        expectDisplay("10m * 2s to cm*s", "2,000 cm·s")
        expectDisplay("2kg / 4m3", "0.5 kg/m³")
        expectDisplay("1kg/m3 + 1g/cm3", "1.001 g/cm³")
        expectDisplay("100 USD / 4hr", "25 USD/hr")
        expectDisplay("25 USD/hr * 8hr", "200.00 USD")
        expectDisplay("8hr * 25 USD/hr", "200.00 USD")
        expectDisplay("25 USD/hr to EUR/min", "0.3833333333 EUR/min")
        expectDisplay("25 USD/hr / 23 EUR/hr", "1")
        expectErrorWithoutRates("25 USD/hr to EUR/hr", "Exchange rates unavailable — check your connection.")
        expectError("2 celsius * 3m", "Multiplication of these unit values is not supported.")
        expectDisplay("1 / 1kg", "1 kg^-1")
        expectDisplay("(2m)^2", "4 m²")
        expectDisplay("5m * 4m to ft2", "215.2782083 ft²")
        expectDisplay("2m * 30cm", "0.6 m²")
        expectDisplay("2m * 3m * 4m to l", "24,000 L")
        expectDisplay("1 ft³ to l", "28.31684659 L")
        expectDisplay("1m3", "1,000 L")
        expectDisplay("1cm3", "1 mL")
        expectDisplay("1dm³ to l", "1 L")
        expectDisplay("(2dm)^3 to l", "8 L")
        expectDisplay("1dL to cl", "10 cL")
        expectDisplay("3 * 2cl 5ml to ml", "75 mL")
        expectDisplay("1 fl oz to ml", "29.57352956 mL")
        expectDisplay("250ml to fl oz", "8.453505675 fl oz")
        expectDisplay("2m * 30cm * 40cm to l", "240 L")
        expectDisplay("pi * (10cm)^2 * 30cm to l", "9.424777961 L")
        expectDisplay("4/3 * pi * (10cm)^3 to l", "4.188790205 L")
        expectDisplay("500l / (2m * 1m) to cm", "25 cm")
        expectDisplay("cbrt(8l) to cm", "20 cm")
        expectDisplay("10l / 2min to l/min", "5 L/min")
        expectDisplay("10l/min * 30s to l", "5 L")
        expectDisplay("150l / 10l/min to duration", "15 min")
        expectDisplay("1m³/h to l/min", "16.66666667 L/min")
        expectDisplay("60l/min to m3/h", "3.6 m³/h")
        expectDisplay("2gpm to l/min", "7.570823568 L/min")
        expectError("10l + 2l/min", "Cannot add Volume and Volume Flow Rate.")
        expectNil("1m3/x")
        expectDisplay("100 Mbps to MB/s", "12.5 MB/s")
        expectDisplay("1 MiB/s to Mbps", "8.388608 Mbps")
        expectDisplay("1GB / 10MB/s to s", "100 s")
        expectDisplay("500 Mbps in MBps", "62.5 MBps")
        expectCopy("500 Mbps in MBps", "62.5 MBps")
        expectExpression("500 Mbps in MBps", "500 Mbps")
        expectBadges(
            "500 Mbps in MBps", source: "Megabits per Second", target: "Megabytes per Second")
        expectDisplay("62.5 MBps to Mbps", "500 Mbps")
        expectDisplay("500Mbps -> MBps", "62.5 MBps")
        expectDisplay("500 Mbps → MBps", "62.5 MBps")
        expectDisplay("8 bps to Bps", "1 Bps")
        expectDisplay("8 Kbps to kBps", "1 kBps")
        expectDisplay("1 KBps to kbps", "8 Kbps")
        expectDisplay("1 Gbps to GBps", "0.125 GBps")
        expectDisplay("1 TBps to Tbps", "8 Tbps")
        expectDisplay("1 MBps to kBps", "1,000 kBps")
        expectDisplay("1 GBps to MBps", "1,000 MBps")
        expectDisplay("1 TBps to GBps", "1,000 GBps")
        expectDisplay("1 MBps to MB/s", "1 MB/s")
        expectDisplay("8 Mb/s to MBps", "1 MBps")
        expectDisplay("1 MiB/s to MBps", "1.048576 MBps")
        expectDisplay("MBps Mbps", "8 Mbps")
        expectDisplay("1 Bps", "8 bps")
        expectDisplay("1 kBps", "8 Kbps")
        expectDisplay("1 MBps", "8 Mbps")
        expectDisplay("1 GBps", "8 Gbps")
        expectDisplay("1 TBps", "8 Tbps")
        expectDisplay("500 Mbps + 62.5 MBps", "125 MBps")
        expectDisplay("1GB / 10MBps to s", "100 s")
        expectDisplay("8kbit to B", "1,000 B")
        expectDisplay("1um to nm", "1,000 nm")
        expectDisplay("1 GHz to MHz", "1,000 MHz")
        expectDisplay("500 microseconds to ms", "0.5 ms")
        expectDisplay("1ton to kg", "1,000 kg")
        expectDisplay("1stone to kg", "6.35029318 kg")
        expectDisplay("1nmi to km", "1.852 km")
        expectDisplay("1ukgal to l", "4.54609 L")
        expectDisplay("1ukpint to ml", "568.26125 mL")
        expectDisplay("100hp to kw", "74.56998716 kW")
        expectDisplay("3000rpm to hz", "50 Hz")
        expectDisplay("1btu to kj", "1.055055853 kJ")
        expectDisplay("1lbf to n", "4.448221615 N")
        expectDisplay("3000px / 300ppi to inches", "10 in")
        expectDisplay("5in * 300PPI", "1,500 px")
        expectCopy("5in * 300ppi", "1500px")
        expectDisplay("300ppi * 5in", "1,500 px")
        expectDisplay("3000 pixels / 10in to ppi", "300 ppi")
        expectBadges("3000px / 10in", source: "Expression", target: "Pixels per Inch")
        expectDisplay("3000px / 300px/in to cm", "25.4 cm")
        expectDisplay("300ppi to px/cm", "118.1102362 px/cm")
        expectDisplay("100px/cm to ppi", "254 ppi")
        expectDisplay("1px/mm to ppi", "25.4 ppi")
        expectDisplay("100px/m * 1m", "100 px")
        expectDisplay("300ppi", "118.1102362 px/cm")
        expectDisplay("1920px * 1080px", "2,073,600 px²")
        expectDisplay("sqrt(9px²)", "3 px")
        expectDisplay("sqrt((3840px)^2 + (2160px)^2) / 27in", "163.1783089 ppi")
        expectDisplay("(300ppi * 2.54cm) / 300px", "1")
        expectError("3000px to cm", "Cannot convert Pixels to Length.")
        expectError("10px + 1in", "Cannot add Pixels and Length.")
        expectNil("3000px / 0ppi")
        expectNil("pixels")
        expectDisplay("16px to rem", "1 rem")
        expectDisplay("1.5rem to px", "24 px")
        expectCopy("1.5rem to px", "24px")
        expectCopy("24px", "1.5rem")
        expectCopy("2000rem", "32000px")
        expectCopy("1rem + 8px", "24px")
        expectCopy("300ppi to px/cm", "118.1102362 px/cm")
        expectDisplay("rem to px", "16 px")
        expectDisplay("rem px", "16 px")
        expectDisplay("24px", "1.5 rem")
        expectBadges("24px", source: "Pixels", target: "REM")
        expectDisplay("2rem", "32 px")
        expectDisplay("2em", "32 px")
        expectDisplay("0.875 rems", "14 px")
        expectDisplay("1em to rem", "1 rem")
        expectDisplay("1rem + 8px", "24 px")
        expectDisplay("8px + 1rem", "1.5 rem")
        expectDisplay("2rem * 3", "6 rem")
        expectDisplay("32px / 1rem", "2")
        expectDisplay("48rem / 96ppi to in", "8 in")
        expectError("1rem to cm", "Cannot convert Pixels to Length.")
        expectNil("rem")
        expectDisplay("20m2 / 4m", "5 m")
        expectDisplay("sqrt(25m2)", "5 m")
        expectDisplay("cbrt(-8m3)", "-2 m")
        expectDisplay("pi * (2m)^2 to m2", "12.56637061 m²")
        expectDisplay("sin(30deg) * 10m", "5 m")
        expectDisplay("100km / 2h to km/h", "50 km/h")
        expectDisplay("90km/h * 20min to km", "30 km")
        expectDisplay("100km / 50km/h to h", "2 hr")
        expectDisplay("1GB / 100mbps to s", "80 s")
        expectDisplay("1500w * 2h to kwh", "3 kWh")
        expectDisplay("5 watt * 3h 30min", "17.5 Wh")
        expectDisplay("3h 30min * 5 watt", "17.5 Wh")
        expectDisplay("5 watt * 3h 30min to kwh", "0.0175 kWh")
        expectDisplay("5 watt * 3h 30min to j", "63,000 J")
        expectCopy("5 watt * 3h 30min", "17.5 Wh")
        expectDisplay("5w * 3h 30min + 2wh", "19.5 Wh")
        expectDisplay("2kw * 3h 30min", "7 kWh")
        expectDisplay("5w * 30s", "150 J")
        expectDisplay("12V * 2A", "24 W")
        expectDisplay("12V / 6ohm", "2 A")
        expectDisplay("12V / 2A", "6 Ω")
        expectDisplay("2A * 6Ω", "12 V")
        expectDisplay("24W / 12V", "2 A")
        expectDisplay("500mA * 3h 30min", "1,750 mAh")
        expectDisplay("2000mAh / 500mA to hours", "4 hr")
        expectDisplay("12V * 2Ah to wh", "24 Wh")
        expectDisplay("10Wh / 5V to mah", "2,000 mAh")
        expectDisplay("3600 coulombs to ah", "1 Ah")
        expectDisplay("1mW to W", "0.001 W")
        expectDisplay("500mA", "0.5 A")
        expectDisplay("1MW to W", "1,000,000 W")
        expectDisplay("1MWh to kwh", "1,000 kWh")
        expectDisplay("1mΩ to ohm", "0.001 Ω")
        expectDisplay("1MΩ to ohm", "1,000,000 Ω")
        expectDisplay("2 * 5feet 3inches", "10.5 ft")
        expectDisplay("90km / 1h 30min to km/h", "60 km/h")
        expectDisplay("2 * 1h 30min 15s to s", "10,830 s")
        expectError("5w * 3h + 30min", "Cannot add Energy and Time.")
        expectNil("5w * 3h 30")
        expectDisplay("10n / 2m2 to pa", "5 Pa")
        expectDisplay("10m/s / 2s", "5 m/s²")
        expectDisplay("2kg * 3m/s²", "6 N")
        expectDisplay("1 / 20ms to hz", "50 Hz")
        expectDisplay("(1hr + 30min) to timespan", "1 hr 30 min")
        expectDisplay("100km / 40km/h to duration", "2 hr 30 min")
        expectNil("1m / 0s")
        expectDisplay("(2m)^0.5", "1.414213562 m^0.5")
        expectDisplay("sqrt(4kg)", "2 kg^0.5")
        expectNil("1kg!")
        expectDisplay("10kg +", "10 kg")
        expectCopy("10kg +", "10 kg")
        expectExpression("10kg +", "10 kg +")
        expectBadges("10kg +", source: "Expression", target: "Kilograms")
        expectNil("10kg + nonsense")
        expectNil("10unknown + 5unknown")
        expectNil("10kg / 0")
        expectDisplay("1234kg + 1kg", "1,235 kg")
        expectCopy("1234kg + 1kg", "1235 kg")

        // 日期/时间 —— 针对固定时钟求值：2026-07-24 周五 00:18 UTC
        expectDisplayAt("hrs till 9am", "8.7 hours")
        expectBadgesAt("hrs till 9am", source: "12:18 AM", target: "9:00 AM")
        expectDisplayAt("hrs till july", "8,207.7 hours")
        expectBadgesAt("hrs till july", source: "12:18 AM", target: "12:00 AM")
        expectDisplayAt("days till 9april", "259 days")
        expectBadgesAt(
            "days till 9april", source: "Friday, 24 July", target: "Friday, 9 April, 2027")
        expectDisplayAt("days till july", "342 days")
        expectBadgesAt(
            "days till july", source: "Friday, 24 July", target: "Thursday, 1 July, 2027")
        expectDisplayAt("days until tomorrow", "1 day")
        expectDisplayAt("weeks till 9april", "37 weeks")  // 259 / 7
        expectDisplayAt("today + 3 weeks", "14 August")
        expectDisplayAt("now + 90 min", "24 July at 1:48 AM")
        expectDisplayAt("jul 4 - today", "345 days")
        expectBadgesAt("jul 4 - today", source: "Sunday, 4 July, 2027", target: "Friday, 24 July")
        // 带空格的运算符算术仍须是普通数学，而不是日期运算
        expectDisplayAt("10 - 3", "7")
        expectDisplayAt("450 + 20%", "540")
        // 不含字母的 `m/d - m/d` 是分数运算，不是日期差。
        expectDisplayAt("5/2 - 1/2", "2")
        expectDisplayAt("3/4 - 1/4", "0.5")
        expectDisplayAt("1/2 - 1/4", "0.25")
        // 当另一侧是关键字时，斜杠日期仍按日期解读
        expectDisplayAt("9/4 - today", "42 days")
        expectDisplayAt("today - 9/4", "-42 days")
        // 指向单一时刻的单词会作答；会重复出现的仍是应用搜索
        expectDisplayAt("today", "24 July")
        expectDisplayAt("tomorrow", "25 July")
        expectDisplayAt("yesterday", "23 July")
        expectDisplayAt("now", "24 July at 12:18 AM")
        expectBadgesAt("tomorrow", source: "Friday, 24 July", target: "Saturday")
        expectExpression("Today", "Today")
        expectDisplayAt("time", "12:18 AM")
        expectBadgesAt("time", source: "Friday, 24 July", target: "UTC")
        expectNilAt("july")
        expectNilAt("monday")
        expectNilAt("noon")
        expectNilAt("todays")
        expectNilAt("times")

        // 角度单位（deg 现在是真实单位，不只是三角函数后缀）
        expectDisplay("1 deg", "0.01745329252 rad")
        expectExpression("1 deg", "1 deg")
        expectBadges("1 deg", source: "Degrees", target: "Radians")
        expectDisplay("90 deg to rad", "1.570796327 rad")
        expectDisplay("1 rad to deg", "57.29577951 deg")
        expectDisplay("1 turn to deg", "360 deg")
        expectDisplay("200 grad to deg", "180 deg")

        // 无数字换算的隐含量值 1
        expectDisplay("day to s", "86,400 s")
        expectDisplay("deg to rad", "0.01745329252 rad")
        expectDisplay("m to ft", "3.280839895 ft")

        // `unit unit` 简写 → 第一个单位的 1 换算为第二个单位
        expectDisplay("day s", "86,400 s")
        expectBadges("day s", source: "Days", target: "Seconds")
        expectDisplay("days s", "86,400 s")
        expectDisplay("hr min", "60 min")
        expectNil("m s")  // 不同类别 → 不出卡片也不报错

        // 额外的单位类别：速度 / 压力 / 数据速率
        expectDisplay("100 kmh to mph", "62.13711922 mph")
        expectDisplay("60 mph to kmh", "96.56064 km/h")
        expectDisplay("100 mbps to kbps", "100,000 Kbps")
        expectBadges("100 kmh to mph", source: "Kilometers per Hour", target: "Miles per Hour")

        // 裸单位自动换算的补齐：同类别同样处理。
        expectDisplay("5 mbar", "0.07251886887 psi")
        expectDisplay("5 kPa", "0.7251886887 psi")
        expectDisplay("5 hPa", "0.07251886887 psi")
        expectDisplay("5 mmHg", "0.0966838873 psi")
        expectDisplay("5 Torr", "0.09668387352 psi")
        expectDisplay("100 bps", "0.1 Kbps")
        expectDisplay("1 Tbps", "1,000 Gbps")

        // 进制换算像单位换算一样接受值一侧的表达式。
        expectDisplay("2*128 to hex", "0x100")
        expectDisplay("10*5 to hex", "0x32")

        // 百分比的各种说法
        expectDisplay("20% off 500", "400")
        expectDisplay("50 as % of 200", "25%")

        // 此前没有徽标的路径现在有了徽标
        expectBadges("255 to hex", source: "Decimal", target: "Hexadecimal")
        expectBadges("0xff to decimal", source: "Hexadecimal", target: "Decimal")
        expectBadges("3*3", source: "Expression", target: "Result")
        expectBadges("20% off 500", source: "Expression", target: "Discounted")

        // days since —— 已过去的时长，基于固定时钟（2026-07-24 周五）
        expectDisplayAt("days since 9jul", "15 days")
        expectBadgesAt("days since 9jul", source: "Thursday, 9 July", target: "Friday, 24 July")
        expectDisplayAt("weeks since 3jul", "3 weeks")
        expectDisplayAt("days since yesterday", "1 day")
        // 答案的星期即徽标，因此日期本身不再重复它。
        expectBadgesAt("today + 3 weeks", source: "Friday, 24 July", target: "Friday")

        // 货币 —— 基于下方固定的 `fx` 表（1 USD = 0.92 EUR = 0.79 GBP = 157 JPY）
        expectDisplay("1 euro to dollars", "1.09 USD")
        expectExpression("1 euro to dollars", "1 EUR")
        expectBadges("1 euro to dollars", source: "Euro", target: "US Dollar")
        expectDisplay("50 GBP in euros", "58.23 EUR")
        expectDisplay("100 dollars to yen", "15,700.00 JPY")
        expectDisplay("100 usd -> eur", "92.00 EUR")
        expectDisplay("2*50 usd to eur", "92.00 EUR")  // 值一侧是表达式
        expectDisplay("eur to usd", "1.09 USD")  // 隐含量值 1
        expectCopy("100 dollars to yen", "15700.00 JPY")
        // 货币符号，可前置也可后置
        expectDisplay("€20 to GBP", "17.17 GBP")
        expectDisplay("20€ to GBP", "17.17 GBP")
        expectDisplay("USD1K to EUR", "920.00 EUR")
        expectDisplay("1kUSD to EUR", "920.00 EUR")
        expectDisplay("£50 in dollars", "63.29 USD")
        expectDisplay("$100 to yen", "15,700.00 JPY")
        // 不足一分的交叉汇率会展开位数，而不是塌缩为 0.00
        expectDisplay("1 jpy to usd", "0.006369 USD")
        // ……且在超过 1e-5 后仍为普通记法，而 "%g" 会翻转为 "5.539e-05"
        expectDisplay("1 idr to usd", "0.00005539 USD")
        expectCopy("1 idr to usd", "0.00005539 USD")
        // 货币不会抢走单位表能回答的查询
        expectDisplay("10 pounds to kilograms", "4.5359237 kg")
        expectDisplay("10 pounds", "4.5359237 kg")
        expectDisplay("10 pounds to euros", "11.65 EUR")
        expectBadges("10 pounds to euros", source: "British Pound", target: "Euro")
        // 货币 ↔ 单位是友好的类别错误，如同重量 ↔ 时间
        expectError("10 usd to kg", "Cannot convert Currency to Weight.")
        expectError("10 kg to usd", "Cannot convert Weight to Currency.")
        // 快照未报价的已知货币，以及完全没有快照的情况
        expectError("5 usd to npr", "No exchange rate for NPR.")
        expectErrorWithoutRates(
            "1 eur to usd", "Exchange rates unavailable — check your connection.")
        expectNil("10 usd to nonsense")
        expectNil("usd")  // 单独的代码仍是应用搜索
        expectNil("btc")  // ……单独的 ticker 也不过是单独的代码
        // 该表由 feed 生成，因此 "no rate" 正是被识别出来的证明。
        expectError("5 usd to zmw", "No exchange rate for ZMW.")
        expectError("5 usd to afn", "No exchange rate for AFN.")
        check(
            "CurrencyData sizes", expected: "true",
            got:
                "\(CurrencyData.all.count >= 150 && CurrencyData.signs.count >= 20 && CurrencyData.aliases.count >= 100)"
        )
        // 已停用代码被过滤掉，因此无人使用的货币不会遮蔽仍在流通的货币
        expectNil("1 hrk to usd")
        expectNil("1 kuna to usd")
        // 徽标来自 CLDR 的标签，在关键之处比注册表名称更短
        expectBadges("1 chf to usd", source: "Swiss Franc", target: "US Dollar")
        expectBadges("1 aed to usd", source: "UAE Dirham", target: "US Dollar")
        // 仅被一种货币主张的名词是生成的 —— 没有人手工输入这些
        expectError("1 zloty to usd", "No exchange rate for PLN.")
        expectError("1 forint to usd", "No exchange rate for HUF.")
        expectError("1 taka to usd", "No exchange rate for BDT.")
        expectError("1 rand to usd", "No exchange rate for ZAR.")
        // 带重音的名词无论是否输入重音都能解析
        expectError("1 krónur to usd", "No exchange rate for ISK.")
        expectError("1 kronur to usd", "No exchange rate for ISK.")
        // 多种货币共享的名词属于手写部分，它们仍必须胜出
        expectDisplay("1 franc to usd", "1.23 USD")
        expectError("1 peso to usd", "No exchange rate for MXN.")
        // `krona` 存在争议（SEK 对 ISK），被刻意不分配给任何一方
        expectNil("1 krona to usd")
        // ISO 4217 对 CNY 的名称是 "Yuan Renminbi"；CLDR 只有 "Chinese Yuan"
        expectError("1 rmb to usd", "No exchange rate for CNY.")
        expectError("1 renminbi to usd", "No exchange rate for CNY.")
        // CLDR 将 TWD 记为 "NT$"，因此台湾用户会输入 `ntd`；`twd` 仍可用
        expectError("1 ntd to usd", "No exchange rate for TWD.")
        expectError("1299 usd to ntd", "No exchange rate for TWD.")
        // 俚语不再支持：CLDR 没有 "quid"，我们也不手工维护同义词
        expectNil("50 quid to usd")
        expectNil("100 bucks to eur")
        // 名称的最后一个词并不总是它的名词 —— 例如 Special Drawing Rights。
        expectNil("1 rights to usd")
        // 小到无法显示的结果读作干净的零，绝不是 "-0.00"
        expectDisplay("-0.0000000000001 usd to eur", "0.00 EUR")
        expectDisplay("0 usd to eur", "0.00 EUR")
        expectDisplay("-5 usd to eur", "-4.60 EUR")
        // CUP（古巴比索）是与单位冲突的生成代码；体积单位仍然胜出
        expectDisplay("1 cup to ml", "236.5882365 mL")

        // 货币表达式 —— 基于注入的汇率表，依然纯粹且确定
        expectDisplay("10$", "10.00 USD")
        expectExpression("10$", "10 USD")
        expectBadges("10$", source: "Expression", target: "US Dollar")
        expectDisplay("$10 + $5", "15.00 USD")
        expectDisplay("10$ + 5$", "15.00 USD")
        expectDisplay("$10 + €5", "14.20 EUR")
        expectDisplay("€5 + $10", "15.43 USD")
        // 符号前置的金额像其他量值一样按金额前置回显
        expectExpression("$10 + €5", "10 USD + 5 EUR")
        expectExpression("10$ + 5€", "10 USD + 5 EUR")
        expectDisplay("$10 * 2", "20.00 USD")
        expectDisplay("$10 / 4", "2.50 USD")
        expectDisplay("$10 / $2", "5")
        expectDisplay("$100 * 3%", "3.00 USD")
        expectDisplay("3% * $100", "3.00 USD")
        expectDisplay("$100 / 25%", "400.00 USD")
        expectDisplay("($100 * 3%) to eur", "2.76 EUR")
        expectDisplay("($10 + $5) to eur", "13.80 EUR")
        // 带括号的换算是一个量值，因此可以相乘或相加。
        expectDisplay("(20 eur to usd) * 30", "652.17 USD")
        expectDisplay("(20 eur to usd) * 20", "434.78 USD")
        expectDisplay("(20 sgd to usd) * 30", "444.44 USD")
        expectDisplay("2 * (20 eur to usd)", "43.48 USD")
        expectDisplay("(20 eur to usd) / 2", "10.87 USD")
        expectDisplay("(eur to usd) * 2", "2.17 USD")  // 隐含量值 1
        expectDisplay("(20 eur to usd) + (10 gbp to usd)", "34.40 USD")
        expectDisplay("((20 eur to usd) + 1) * 2", "45.48 USD")
        expectDisplay("(10km to mi) * 2", "12.42742384 mi")
        expectDisplay("(1hr + 30min to s) * 2", "10,800 s")
        expectExpression("(20 eur to usd) * 30", "(20 EUR to USD) × 30")
        expectBadges("(20 eur to usd) * 30", source: "Expression", target: "US Dollar")
        expectDisplay("(20 eur to usd) *", "21.74 USD")
        expectError("(10 kg to usd) * 2", "Cannot convert Weight to Currency.")
        // 尾随后缀通过该分组所用的同一次换算来报告。
        expectError("($10 + $5) to npr", "No exchange rate for NPR.")
        expectError("(1kg + 500g) to usd", "Cannot convert Weight to Currency.")
        // 表达式中间的 `to` 在相加前先换算；`* 30` 仍有歧义，因此需要括号
        expectNil("20 eur to usd * 30")
        expectNil("20 eur to usd / 2")
        expectDisplay("20 eur to usd + 5 usd", "26.74 USD")
        expectDisplay("$10 +", "10.00 USD")
        expectBadges("$10 +", source: "Expression", target: "US Dollar")
        // 并列写在金额任一侧都表示相乘，与显式 "*" 相同
        expectDisplay("$5(2)", "10.00 USD")
        expectDisplay("5(2)$", "10.00 USD")
        expectDisplay("$5(2) to eur", "9.20 EUR")
        expectError("$10 + 5kg", "Cannot add Currency and Weight.")
        expectErrorWithoutRates(
            "$10 + $5", "Exchange rates unavailable — check your connection.")
        expectErrorWithoutRates(
            "$100 * 3%", "Exchange rates unavailable — check your connection.")
        expectErrorWithoutRates(
            "10$", "Exchange rates unavailable — check your connection.")

        // 加密货币 —— 由同一张表定价，因此币对法币的换算无需特例
        expectDisplay("1 btc to usd", "60,000.00 USD")
        expectDisplay("1 bitcoin to usd", "60,000.00 USD")
        expectDisplay("0.5 sol to eur", "46.00 EUR")
        expectDisplay("2 eth to gbp", "3,160.00 GBP")
        expectBadges("1 eth to usd", source: "Ethereum", target: "US Dollar")
        // 不足一分的展开对币的处理与对 IDR 相同
        expectDisplay("1 usd to btc", "0.00001667 BTC")
        expectCopy("1 usd to btc", "0.00001667 BTC")
        // feed 未包含的符号，行为与未被报价的法币代码完全一致
        expectError("1 shib to usd", "No exchange rate for SHIB.")
        // ticker 会被识别，而不是被单位表吞掉
        expectError("1 dash to usd", "No exchange rate for DASH.")
        expectError("1 neo to usd", "No exchange rate for NEO.")
        // ticker 优先于生成的名词，且仅限于该名词：`soles` 仍会到达 PEN
        expectBadges("1 sol to usd", source: "Solana", target: "US Dollar")
        expectError("1 soles to usd", "No exchange rate for PEN.")
        check(
            "crypto is absent from the generated fiat table", expected: "true",
            got: "\(CurrencyData.all.allSatisfy { !CalcCurrency.cryptoCodes.contains($0.code) })")

        // 裸金额以 Mac 所在区域的货币作答，该区域是注入的，绝不直接读取
        expectDisplay("1 usd", "83.50 INR", region: "INR")
        expectExpression("1 usd", "1 USD", region: "INR")
        expectBadges("1 usd", source: "US Dollar", target: "Indian Rupee", region: "INR")
        expectDisplay("10$", "835.00 INR", region: "INR")
        expectDisplay("1 btc", "5,010,000.00 INR", region: "INR")
        expectCopy("1 usd", "83.50 INR", region: "INR")
        // 区域指定了所写的货币，因此美元改为与欧元配对
        expectDisplay("1 usd", "0.92 EUR", region: "USD")
        expectBadges("1 usd", source: "US Dollar", target: "Euro", region: "USD")
        expectDisplay("1 eur", "1.09 USD", region: "EUR")
        expectBadges("1 eur", source: "Euro", target: "US Dollar", region: "EUR")
        // 无可奉告：区域指定的货币无人报价，或根本没有区域
        expectDisplay("1 usd", "1.00 USD", region: "NPR")
        expectDisplay("1 usd", "1.00 USD", region: "ZZZ")
        expectDisplay("1 usd", "1.00 USD")
        // 运算符、目标或半输入表达式都会保留所写的货币
        expectDisplay("$10 + €5", "14.20 EUR", region: "INR")
        expectDisplay("$10 +", "10.00 USD", region: "INR")
        expectBadges("$10 +", source: "Expression", target: "US Dollar", region: "INR")
        expectDisplay("1 usd to eur", "0.92 EUR", region: "INR")
        expectDisplay("10 pounds", "4.5359237 kg", region: "INR")
        expectNil("usd", region: "INR")
        expectNil("btc", region: "INR")

        // feed 解码，按 store 交付它的方式进行测试
        expectSnapshot(
            "fiat only", fiat: fiatJSON, crypto: nil,
            expected: "USD=1 EUR=0.9 BTC=nil complete=false")
        expectSnapshot(
            "both feeds", fiat: fiatJSON, crypto: cryptoJSON,
            expected: "USD=1 EUR=0.9 BTC=5e-05 complete=true")
        // 以其他基准报价的币种载荷会被忽略，而不是被错误地并入
        expectSnapshot(
            "mismatched base", fiat: fiatJSON,
            crypto: Data(#"{"success":true,"target":"EUR","rates":{"BTC":20000}}"#.utf8),
            expected: "USD=1 EUR=0.9 BTC=nil complete=false")
        expectSnapshotThrows("no quotes", fiat: Data(#"{"success":true,"source":"USD","quotes":{}}"#.utf8))
        // 未给任何币定价的缓存快照早于这些币，无论其 `fetchedAt` 怎么说
        let coinless = CurrencyRates(base: "USD", rates: ["EUR": 0.9], fetchedAt: clock.now)
        check(
            "a coin-less snapshot is rejected on load", expected: "false",
            got: "\(CurrencyFeed.pricesCoins(coinless))")
        check("the fixture prices coins", expected: "true", got: "\(CurrencyFeed.pricesCoins(fx))")
        expectSnapshotThrows(
            "feed reported failure",
            fiat: Data(#"{"success":false,"source":"USD","quotes":{"USDEUR":0.9}}"#.utf8))

        // 带斜杠的速率写法 —— 分词器会把已知的 `unit/unit` 保持完整
        expectDisplay("100 km/h to mph", "62.13711922 mph")
        expectDisplay("60 mph in km/h", "96.56064 km/h")
        expectDisplay("5 m/s to km/h", "18 km/h")
        expectDisplay("100 km/h", "62.13711922 mph")
        expectExpression("100 km/h to mph", "100 km/h")
        expectBadges("5 m/s to km/h", source: "Meters per Second", target: "Kilometers per Hour")
        expectDisplay("100 mbit/s to mbps", "100 Mbps")
        // 未知配对会把斜杠留作除法，因此普通算术不受影响
        expectDisplay("10/2", "5")
        expectDisplay("6/2(1+2)", "9")
        expectDisplay("10 m / 2", "5 m")
        expectNil("1 km/x")

        // 工作日是 8 小时；周末和假日是日历的事，不是单位的事
        expectDisplay("55h in workdays", "6.875 workdays")
        expectDisplay("3 workdays in hours", "24 hr")
        expectDisplay("2 businessdays to hours", "16 hr")
        expectBadges("55h in workdays", source: "Hours", target: "Workdays")

        // 三角函数集的其余部分，以及随之而来的常量
        expectDisplay("cot(1)", "0.6420926159")
        expectDisplay("sec(1)", "1.850815718")
        expectDisplay("csc(1)", "1.188395106")
        expectDisplay("asin(1)", "1.570796327")
        expectDisplay("acos(1)", "0")
        expectDisplay("arctan(1)", "0.7853981634")
        expectDisplay("sinh(1)", "1.175201194")
        expectDisplay("tanh(0)", "0")
        expectDisplay("cbrt(27)", "3")
        expectDisplay("log2(1024)", "10")
        expectDisplay("exp(0)", "1")
        expectDisplay("sign(-5)", "-1")
        expectDisplay("trunc(3.7)", "3")
        expectDisplay("2 tau", "12.56637061")
        expectDisplay("phi * 2", "3.236067977")
        // `sec` 也是秒，处于单位位置时仍然胜出
        expectDisplay("10 sec to min", "0.1666666667 min")
        expectDisplay("30 sec + 1 min", "1.5 min")

        // 百分比与比例的各种说法
        expectDisplay("15% tip on 42", "6.3")
        expectDisplay("20% tip of 80", "16")
        expectDisplay("50 is what % of 200", "25%")
        expectDisplay("30 is 20% of what", "150")
        expectDisplay("ratio of 3 to 5", "3 : 5")
        expectDisplay("ratio of 4 to 6", "2 : 3")
        expectDisplay("ratio of 1920 to 1080", "16 : 9")
        expectBadges("15% tip on 42", source: "Expression", target: "Tip")

        // 列表聚合与就近取整，二者都需要逗号 token
        expectDisplay("average of 10, 20, 30", "20")
        expectDisplay("avg of 1 and 2 and 3", "2")
        expectDisplay("sum of 10, 20, 30", "60")
        expectDisplay("max of 4, 9, 2", "9")
        expectDisplay("min of 4, 9, 2", "2")
        expectDisplay("sum of 2*3, 4", "10")
        expectDisplay("round 47 to nearest 5", "45")
        expectDisplay("round 12.3 to nearest 0.5", "12.5")
        // 数字之间的逗号仍是分组分隔符，且单个操作数不构成列表
        expectDisplay("1,000 + 234", "1,234")
        expectNil("average of 5")
        expectNil("10,5")

        // timespan 会把时长拆成合适的单位
        expectDisplay("145 mins to timespan", "2 hr 25 min")
        expectDisplay("1 month to timespan", "4 wk 2 day 10 hr 29 min 6 s")
        expectDisplay("8700 s to timespan", "2 hr 25 min")
        expectDisplay("90000 s to timespan", "1 day 1 hr")
        expectDisplay("55 h to timespan", "2 day 7 hr")
        expectDisplay("1000000 s to timespan", "1 wk 4 day 13 hr 46 min 40 s")
        expectBadges("145 mins to timespan", source: "Minutes", target: "Timespan")
        expectNil("10 km to timespan")

        expectDisplayAt("1970-01-01T00:00:00Z to unix", "0")
        expectDisplayAt("1970-01-01T01:00:00+01:00 to unix", "0")
        expectDisplayAt("1970-01-01T00:00:00.125Z to unix ms", "125")
        expectDisplayAt("1970-01-01T00:00:00.002Z to unix ms", "2")
        expectDisplayAt("1969-12-31T23:59:59.999Z to unix ms", "-1")
        expectDisplayAt("unix 1234567890.125 to unix ms", "1,234,567,890,125")
        expectDisplayAt("1970-01-01T00:00:00Z + 1h to unix", "3,600")
        expectDisplayAt("unix 0 to date", "1 January, 1970 at 12:00 AM")
        expectDisplayAt("1970-01-01T00:00:00Z to date", "1 January, 1970 at 12:00 AM")
        expectDisplayAt("1000 unix ms", "1 January, 1970 at 12:00:01 AM")
        expectDisplayAt("unix -1", "31 December, 1969 at 11:59:59 PM")
        expectDisplayAt("2026-07-24T07:30:00+02:00 + 30min", "24 July at 6:00 AM")
        expectNilAt("2026-02-30T00:00:00Z")
        expectNilAt("2026-07-24T00:00:00Z junk")
        expectNilAt("unix 1e30")

        // 时区。时钟固定为 UTC，因此每一项都精确。
        expectDisplayAt("time in tokyo", "9:18 AM")
        expectDisplayAt("time in sf", "5:18 PM (yesterday)")
        expectDisplayAt("what time is it in london", "1:18 AM")
        expectDisplayAt("time in kolkata", "5:48 AM")
        expectDisplayAt("time in utc", "12:18 AM")
        expectBadgesAt("time in tokyo", source: "UTC", target: "Tokyo")
        expectBadgesAt("time in sf", source: "UTC", target: "Los Angeles")
        // 具名源时区会覆盖 Mac 自身的时区，因此两侧都不必是本地
        expectDisplayAt("5pm london in sf", "9:00 AM")
        expectDisplayAt("9:30am in nyc", "5:30 AM")
        expectDisplayAt("5pm in tokyo", "2:00 AM (tomorrow)")
        expectBadgesAt("5pm london in sf", source: "London", target: "Los Angeles")
        // 由 locale 的小时周期决定时钟，24 小时制开关会覆盖它
        var hour24 = clock.calendar
        hour24.locale = Locale(identifier: "en_US@hours=h23")
        var britain = clock.calendar
        britain.locale = Locale(identifier: "en_GB")
        var britain12 = clock.calendar
        britain12.locale = Locale(identifier: "en_GB@hours=h12")
        expectDisplayAt("time in tokyo", "09:18", calendar: hour24)
        expectDisplayAt("5pm in tokyo", "02:00 (tomorrow)", calendar: hour24)
        expectDisplayAt("unix -1", "31 December, 1969 at 23:59:59", calendar: hour24)
        expectDisplayAt("now + 90 min", "24 July at 01:48", calendar: hour24)
        expectDisplayAt("time in sf", "17:18 (yesterday)", calendar: britain)
        expectBadgesAt("hrs till 9am", source: "00:18", target: "09:00", calendar: britain)
        expectDisplayAt("time in sf", "5:18 pm (yesterday)", calendar: britain12)

        let zoneNow = clock.calendar.date(
            from: DateComponents(year: 2026, month: 9, day: 15, hour: 12))!
        for home in ["UTC", "Asia/Shanghai", "America/Los_Angeles"] {
            var calendar = clock.calendar
            calendar.timeZone = TimeZone(identifier: home)!
            for query in [
                "5:30pm SF to London", "5:30 pm SF to London", "5:30 pm in SF to London",
                "5:30 PM in San Francisco to London", "5:30\u{a0}pm SF to London",
                "5:30 pm SF in London", "5:30 pm SF at London", "5:30 pm at SF to London",
                "17:30 SF to London"
            ] {
                expectDisplayAt(query, "1:30 AM (tomorrow)", now: zoneNow, calendar: calendar)
                expectBadgesAt(
                    query, source: "Los Angeles", target: "London", now: zoneNow, calendar: calendar)
            }
            for query in ["5pm SF to London", "5pm in SF to London", "5 pm in SF to London"] {
                expectDisplayAt(query, "1:00 AM (tomorrow)", now: zoneNow, calendar: calendar)
            }
            for query in [
                "5pm PSTT to London", "5:30 pm PSTT to London", "5pm in PSTT to London",
                "5pm SF junk to London", "5pm in to London", "5pm at to London",
                "5pm pm SF to London", "5pm am SF to London",
                "time in sf in 4 hours", "now in tokyo in 2h",
                "time at sf in 4 hours", "now at tokyo in 2h"
            ] {
                expectNilAt(query, now: zoneNow, calendar: calendar)
            }
        }
        expectDisplayAt("5:30 pm to London", "6:30 PM")
        expectDisplayAt("5 pm in Tokyo", "2:00 AM (tomorrow)")
        expectDisplayAt("5:30 am SF to London", "1:30 PM")
        expectDisplayAt("12 am SF to London", "8:00 AM")
        expectDisplayAt("12 pm SF to London", "8:00 PM")
        expectDisplayAt("5:30 pm in SF to London + 30 min", "2:00 AM (tomorrow)")
        expectCopy("5:30 pm SF to London", "1:30 AM")
        expectNilAt("13 pm SF to London")
        expectNilAt("5:60 pm SF to London")

        let localConversionNow = clock.calendar.date(
            from: DateComponents(year: 2026, month: 9, day: 15, hour: 12))!
        for (home, target, time, dayNote) in [
            ("Asia/Shanghai", "Shanghai", "8:30 AM", " (tomorrow)"),
            ("UTC", "UTC", "12:30 AM", " (tomorrow)"),
            ("America/Los_Angeles", "Los Angeles", "5:30 PM", "")
        ] {
            var calendar = clock.calendar
            calendar.timeZone = TimeZone(identifier: home)!
            let expected = CalcResult(
                expression: "5:30 PM", sourceBadge: "Los Angeles", targetBadge: target,
                payload: .value(display: time + dayNote, copyText: time),
                canChain: false)
            for query in [
                "5:30pm SF", "5:30 pm SF", "17:30 San Francisco", "5:30 PM SFO",
                "  5:30\tpm\u{00A0}sf  "
            ] {
                let result = CalcEngine.evaluate(query, now: localConversionNow, calendar: calendar)
                check("\(query) [home \(home)]", expected: "true", got: "\(result == expected)")
            }
        }
        for components in [
            DateComponents(year: 2026, month: 9, day: 15, hour: 12),
            DateComponents(year: 2026, month: 1, day: 1, hour: 0),
            DateComponents(year: 2026, month: 11, day: 1, hour: 12)
        ] {
            let now = clock.calendar.date(from: components)!
            for (home, destination) in [
                ("UTC", "UTC"), ("Asia/Shanghai", "Shanghai"),
                ("Pacific/Kiritimati", "Kiritimati"), ("Pacific/Pago_Pago", "Pago Pago")
            ] {
                var calendar = clock.calendar
                calendar.timeZone = TimeZone(identifier: home)!
                for (query, explicit) in [
                    ("5 pm SF", "5pm SF"), ("12 am Canada", "12am Canada"),
                    ("12 pm CDG", "12pm CDG"), ("09:15 Kathmandu", "09:15 Kathmandu"),
                    ("23:30 Pago Pago", "23:30 Pago Pago"), ("00:30 Kiritimati", "00:30 Kiritimati"),
                    ("1:30 am SF", "1:30am SF"), ("17:30 São Paulo", "17:30 São Paulo")
                ] {
                    let expected = CalcEngine.evaluate(
                        "\(explicit) to \(destination)", now: now, calendar: calendar)
                    let result = CalcEngine.evaluate(query, now: now, calendar: calendar)
                    check(
                        "\(query) [home \(home), now \(now)]", expected: "true",
                        got: "\(expected != nil && result == expected)")
                }
            }
        }
        expectDisplayAt("5:30 pm SF + 30 min", "1:00 AM (tomorrow)", now: localConversionNow)
        expectDisplayAt("5:30pm SF - 2h", "10:30 PM", now: localConversionNow)
        expectDisplayAt("5:30pm in SF", "10:30 AM", now: localConversionNow)
        expectDisplayAt("5:30pm SF to London", "1:30 AM (tomorrow)", now: localConversionNow)
        expectNilAt(
            "2:30 am SF",
            now: clock.calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))!)
        for query in [
            "5:30 pm PSTT", "5:30pm PSTT", "5:30pm SF junk", "5:30 pm SF London",
            "5pm", "5 pm", "17:30", "17:30 pm", "5 SF", "pm SF", "now SF",
            "13pm SF", "5:60pm SF", "5pm pm SF", "5:30 am pm SF", "25:30 SF",
            "5:30pm SF to", "5:30pm SF to PSTT", "5:30pm SF + 2 kg",
            "time in sf in 4 hours", "now in tokyo in 2h", "Screen Time", "Safari SF"
        ] {
            expectNilAt(query)
        }
        // 别名覆盖标识符没有拼出的内容，DST 则交给 Foundation 自己解答
        expectDisplayAt("time in nyc", "8:18 PM (yesterday)")
        expectDisplayAt("time in cet", "2:18 AM")
        // 时区名永远不会优先于单位或货币，非时区仍是搜索
        expectDisplay("1 cup to ml", "236.5882365 mL")
        expectNil("time in xyzzy")
        expectNil("in tokyo")

        // IATA 机场代码，Foundation 对它没有概念
        expectDisplayAt("time in vie", "2:18 AM")
        expectDisplayAt("time in lhr", "1:18 AM")
        expectDisplayAt("time in nrt", "9:18 AM")
        expectDisplayAt("time in sfo", "5:18 PM (yesterday)")
        expectBadgesAt("time in vie", source: "UTC", target: "Vienna")
        expectDisplayAt("5pm vie in nrt", "12:00 AM (tomorrow)")
        // `mad` 仍是摩洛哥迪拉姆，`ist` 仍是印度标准时间
        expectError("10 mad to usd", "No exchange rate for MAD.")
        expectBadgesAt("time in ist", source: "UTC", target: "Kolkata")

        // 尾随偏移会平移时区答案，因此整体仍是一条查询
        expectDisplayAt("5pm london in sf", "9:00 AM")
        expectDisplayAt("5pm london in sf + 2h", "11:00 AM")
        expectDisplayAt("5pm london in sf - 1 hour", "8:00 AM")
        expectDisplayAt("5pm london in sf + 30 min", "9:30 AM")
        expectBadgesAt("5pm london in sf + 2h", source: "London", target: "Los Angeles")
        // 单位换算不是时区偏移，裸求和也不是
        expectDisplay("1 cup to ml", "236.5882365 mL")
        expectNil("5pm london in sf + 2 kg")

        for components in [
            DateComponents(year: 2026, month: 9, day: 15, hour: 12),
            DateComponents(year: 2026, month: 9, day: 30, hour: 12),
            DateComponents(year: 2026, month: 12, day: 31, hour: 12),
            DateComponents(year: 2026, month: 3, day: 8, hour: 12),
            DateComponents(year: 2026, month: 11, day: 1, hour: 12)
        ] {
            let now = clock.calendar.date(from: components)!
            for home in ["UTC", "Asia/Shanghai", "America/Los_Angeles"] {
                var calendar = clock.calendar
                calendar.timeZone = TimeZone(identifier: home)!
                for (query, expected) in [
                    ("23:30 Pago Pago to Kiritimati", "12:30 AM (in 2 days)"),
                    ("00:30 Kiritimati to Pago Pago", "11:30 PM (2 days ago)"),
                    ("22:59 Pago Pago to Kiritimati", "11:59 PM (tomorrow)"),
                    ("01:00 Kiritimati to Pago Pago", "12:00 AM (yesterday)"),
                    ("12:00 Pago Pago to Pago Pago", "12:00 PM")
                ] {
                    expectDisplayAt(query, expected, now: now, calendar: calendar)
                }
            }
        }
        expectBadgesAt("23:30 Pago Pago to Kiritimati", source: "Pago Pago", target: "Kiritimati")
        expectBadgesAt("00:30 Kiritimati to Pago Pago", source: "Kiritimati", target: "Pago Pago")
        expectCopy("23:30 Pago Pago to Kiritimati", "12:30 AM")
        expectCopy("00:30 Kiritimati to Pago Pago", "11:30 PM")
        expectDisplayAt("23:30 Pago Pago to Kiritimati + 30 min", "1:00 AM (tomorrow)")
        expectDisplayAt("00:30 Kiritimati to Pago Pago + 30 min", "12:00 AM (yesterday)")

        // `<weekday> in <n> weeks` 会给出落在那一周内的该星期几
        expectDisplayAt("monday in 3 weeks", "10 August")
        expectDisplayAt("monday in 1 week", "27 July")
        expectDisplayAt("tuesday in 2 weeks", "4 August")
        expectDisplayAt("friday in 2 weeks", "7 August")
        expectBadgesAt("monday in 3 weeks", source: "Friday, 24 July", target: "Monday")
        // 月份不是星期几，且 `in` 仍会走单位路径
        expectNil("monday in 3 kg")
        expectDisplay("10 in in cm", "25.4 cm")

        // 某时区相对 Mac 自身时区的偏移
        expectDisplayAt("diff paris", "2:18 AM (+2h)")
        expectDisplayAt("time diff tokyo", "9:18 AM (+9h)")
        expectDisplayAt("diff kolkata", "5:48 AM (+5h 30m)")
        expectBadgesAt("diff paris", source: "UTC", target: "Paris")
        expectNil("diff xyzzy")

        // 在时区位置放一个时长，以及两者同时出现
        expectDisplayAt("time in 4 hours", "4:18 AM")
        expectDisplayAt("time in 90 min", "1:48 AM")
        expectDisplayAt("time in 4 hours in san francisco", "9:18 PM (yesterday)")
        expectDisplayAt("time in 4 hours in sf", "9:18 PM (yesterday)")
        expectBadgesAt("time in 4 hours in sf", source: "UTC", target: "Los Angeles")

        // 时钟答案上的裸偏移是小时，即答案本身已隐含的单位
        expectDisplayAt("time in tokyo + 2", "11:18 AM")
        expectDisplayAt("time in tokyo - 2", "7:18 AM (tomorrow)")
        expectDisplayAt("5pm london in sf + 3", "12:00 PM")
        // 只有偏移会隐含它：裸数字仍不构成时区，普通数学不受影响
        expectNilAt("time in 4")
        expectDisplay("5 + 3", "8")

        // 点分日期以日为先，即书写它们的惯例
        expectDisplayAt("19.2.27 + 3", "22 February, 2027")
        expectDisplayAt("19.02.2027 + 3", "22 February, 2027")
        expectDisplayAt("19.2.27 - 3", "16 February, 2027")
        expectDisplayAt("31.12.26 + 1", "1 January, 2027")
        expectDisplayAt("19.2.27 + 3 weeks", "12 March, 2027")
        expectBadgesAt("19.2.27 + 3", source: "Friday, 19 February, 2027", target: "Monday")
        // 小数不是日期，版本号也不是
        expectDisplay("1.5 + 3", "4.5")
        expectDisplay("99.99 + 0.01", "100")
        expectNilAt("1.2.3 + 1")
        expectNilAt("1.5.5 + 3")
        // 不存在的日期同样不出卡片
        expectNilAt("30.2.27 + 1")

        // fuzzer 发现的畸形输入：这两条都会读过 token 数组末尾
        expectNil("round is next round to")
        expectNilAt(": from to at sf")
        expectNil("round to")
        expectNil("round 5 to")
        expectNilAt(": at sf")
        expectNil("is what % of")
        expectNil("tip on")

        // 门控扫描的是空白字符而非字面空格，因此粘贴的 NBSP 依然能被识别。
        expectDisplayAt("time\u{a0}in\u{a0}tokyo", "9:18 AM")
        expectDisplayAt("time\u{9}in\u{9}tokyo", "9:18 AM")
        expectDisplayAt("time\u{2009}in\u{2009}tokyo", "9:18 AM")

        // 德语和奥地利语日期写在日之后的序数点
        expectDisplayAt("28. aug + 3", "31 August")
        expectDisplayAt("28. august + 3", "31 August")
        expectDisplayAt("28.aug + 3", "31 August")
        // 取最近而非下一个：从七月看，一月是六个月前而不是六个月后
        expectDisplayAt("1. jan + 1", "2 January")
        expectDisplayAt("28. aug 2027 + 3", "31 August, 2027")
        expectBadgesAt("28. aug + 3", source: "Friday, 28 August", target: "Monday")
        // 只有尾随的点才是序数，因此小数日仍不是日期
        expectNilAt("28.5 aug + 1")

        // 一个写出的日期本身就是出卡片的理由：星期几正是你输入它的原因
        expectDisplayAt("25. aug", "25 August")
        expectDisplayAt("25 aug", "25 August")
        expectDisplayAt("aug 25", "25 August")
        expectDisplayAt("25.8.27", "25 August, 2027")
        expectDisplayAt("1. jan", "1 January")
        expectBadgesAt("25. aug", source: "Friday, 24 July", target: "Tuesday")
        // 裸日期采用最近的年份，因此与同一日期加偏移的结果一致
        expectDisplayAt("25. aug + 3", "28 August")
        // 单独的月份仍是应用搜索
        expectNilAt("july")
        expectNilAt("aug")

        // 日期运算从左到右串联，无论包含多少项
        expectDisplayAt("17.2.26 + 100 week days - 4 + 2", "5 July")
        expectDisplayAt("17.2.26 + 100 weekdays", "7 July")
        expectDisplayAt("17.2.26 + 100 weekdays - 4", "3 July")
        expectDisplayAt("today + 3 weeks - 2 days", "12 August")
        expectDisplayAt("today + 5 + 2", "31 July")
        expectDisplayAt("today + 1 day + 1 day + 1 day", "27 July")
        expectDisplayAt("now + 90 min + 30 min", "24 July at 2:18 AM")
        expectDisplayAt("3:45pm + 5 - 2", "24 July at 6:45 PM")
        expectBadgesAt("17.2.26 + 100 week days - 4 + 2", source: "Tuesday, 17 February", target: "Sunday")
        // 每一项都必须是时长，因此单位或游离单词仍不出卡片
        expectNilAt("today + 3 weeks - kg")
        expectNilAt("today + 5 - abc")
        // 两个时刻仍是求差，不含字母的操作数仍是算术
        expectDisplayAt("jul 4 - today", "345 days")
        expectDisplay("5 + 3 - 2", "6")
        expectDisplay("5/2 - 1/2", "2")

        // 带重音的拼写也能解析，因为标识符本身不含重音
        expectDisplayAt("time in são paulo", "9:18 PM (yesterday)")
        expectDisplayAt("time in sao paulo", "9:18 PM (yesterday)")
        expectDisplayAt("time in zürich", "2:18 AM")

        // IANA 从未命名的城市，因为它们的时钟与所属时区从未不同
        expectBadgesAt("time in graz", source: "UTC", target: "Vienna")
        expectBadgesAt("time in salzburg", source: "UTC", target: "Vienna")
        expectBadgesAt("time in klagenfurt", source: "UTC", target: "Vienna")
        expectBadgesAt("time in hannover", source: "UTC", target: "Berlin")
        expectBadgesAt("time in stuttgart", source: "UTC", target: "Berlin")
        expectBadgesAt("time in basel", source: "UTC", target: "Zurich")
        expectBadgesAt("time in manchester", source: "UTC", target: "London")
        expectBadgesAt("time in florence", source: "UTC", target: "Rome")
        expectBadgesAt("time in lyon", source: "UTC", target: "Paris")
        expectBadgesAt("time in krakow", source: "UTC", target: "Warsaw")
        // 它们带重音的拼写会归到同一条目
        expectBadgesAt("time in düsseldorf", source: "UTC", target: "Berlin")
        expectBadgesAt("time in kraków", source: "UTC", target: "Warsaw")
        expectBadgesAt("time in malmö", source: "UTC", target: "Stockholm")
        expectBadgesAt("5pm graz in basel", source: "Vienna", target: "Zurich")

        // 国家以其主时钟作答，并带有该时钟所属城市的徽标
        expectDisplayAt("time in uk", "1:18 AM")
        expectDisplayAt("Time in UK", "1:18 AM")
        expectBadgesAt("time in united kingdom", source: "UTC", target: "London")
        expectBadgesAt("time in japan", source: "UTC", target: "Tokyo")
        expectBadgesAt("what time is it in germany", source: "UTC", target: "Berlin")
        expectBadgesAt("time in côte d’ivoire", source: "UTC", target: "Abidjan")
        expectBadgesAt("time in trinidad and tobago", source: "UTC", target: "Port of Spain")
        expectDisplayAt("5pm uk in japan", "1:00 AM (tomorrow)")
        expectDisplayAt("time in uk + 2", "3:18 AM")
        // 跨多个时区的国家以其首都为准，绝不用偏远边缘
        expectBadgesAt("time in usa", source: "UTC", target: "New York")
        expectBadgesAt("time in us", source: "UTC", target: "New York")
        expectBadgesAt("time in australia", source: "UTC", target: "Sydney")
        expectBadgesAt("time in canada", source: "UTC", target: "Toronto")
        expectBadgesAt("time in russia", source: "UTC", target: "Moscow")
        expectBadgesAt("time in uae", source: "UTC", target: "Dubai")
        // 拼写像国家代码的单位仍是单位
        expectDisplay("10 ms to us", "10,000 µs")
        expectNilAt("time in antarctica")
        check(
            "country zones resolve", expected: "true",
            got: "\(CountryZoneData.zones.values.allSatisfy { TimeZone(identifier: $0) != nil })")

        expectDisplayAt("SF time", "5:18 PM (yesterday)")
        expectDisplayAt("time SF", "5:18 PM (yesterday)")
        expectDisplayAt("current time to Tokyo", "9:18 AM")
        expectDisplayAt("what time is it to Tokyo", "9:18 AM")
        let usaExpected = CalcResult(
            expression: "12:00 PM", sourceBadge: "UTC", targetBadge: "New York",
            payload: .value(display: "8:00 AM", copyText: "8:00 AM"),
            canChain: false)
        let usaNow = CalcEngine.evaluate("now in usa", now: zoneNow, calendar: clock.calendar)
        check("now in usa", expected: "true", got: "\(usaNow == usaExpected)")
        for query in ["Canada timezone", "Canada time zone", "timezone Canada", "timezone in Canada"] {
            let expected = CalcResult(
                expression: "12:00 PM", sourceBadge: "UTC", targetBadge: "Toronto",
                payload: .value(display: "8:00 AM", copyText: "8:00 AM"),
                canChain: false)
            let actual = CalcEngine.evaluate(query, now: zoneNow, calendar: clock.calendar)
            check(query, expected: "true", got: "\(actual == expected)")
        }
        for query in ["Canada time to China", "Canada timezone to China", "Canada time zone to China"] {
            let expected = CalcResult(
                expression: "8:00 AM", sourceBadge: "Toronto", targetBadge: "Shanghai",
                payload: .value(display: "8:00 PM", copyText: "8:00 PM"),
                canChain: false)
            let actual = CalcEngine.evaluate(query, now: zoneNow, calendar: clock.calendar)
            check(query, expected: "true", got: "\(actual == expected)")
        }
        expectDisplayAt("Tokyo time", "9:18 AM")
        expectDisplayAt("  sF\tTiMe  ", "5:18 PM (yesterday)")
        expectDisplayAt("San\u{a0}Francisco\u{2009}time", "5:18 PM (yesterday)")
        expectDisplayAt("Tokyo\ntime", "9:18 AM")
        expectDisplayAt("  TiMe\tSF  ", "5:18 PM (yesterday)")
        expectDisplayAt("SF\u{a0}TiMe\u{2009}ZoNe", "5:18 PM (yesterday)")
        expectDisplayAt("TimeZone\nIn\tTokyo", "9:18 AM")
        expectDisplayAt("Canada\tTiMe\u{a0}ZoNe\tTo\nChina", "8:00 PM", now: zoneNow)
        for components in [
            DateComponents(year: 2026, month: 1, day: 15, hour: 12),
            DateComponents(year: 2026, month: 9, day: 15, hour: 12),
            DateComponents(year: 2026, month: 9, day: 15, hour: 23, minute: 30)
        ] {
            let now = clock.calendar.date(from: components)!
            for home in ["UTC", "Asia/Shanghai", "America/Los_Angeles"] {
                var calendar = clock.calendar
                calendar.timeZone = TimeZone(identifier: home)!
                for place in [
                    "SF", "Tokyo", "London", "Shanghai", "San Francisco", "New York", "Canada",
                    "USA", "United States", "United Kingdom", "India", "South Korea", "PST", "UTC", "GMT",
                    "SFO", "CDG", "LDN", "SÃO PAULO", "Zürich", "Côte d’Ivoire", "Trinidad and Tobago",
                    "Georgia", "Basel", "The Hague", "Swift Current"
                ] {
                    let expected = CalcEngine.evaluate("time in \(place)", now: now, calendar: calendar)
                    for query in [
                        "\(place) TiMe", "time \(place)", "\(place) timezone", "\(place) time zone",
                        "timezone \(place)", "timezone in \(place)", "now in \(place)"
                    ] {
                        let actual = CalcEngine.evaluate(query, now: now, calendar: calendar)
                        check(
                            "\(query) [\(home), \(now)]", expected: "true",
                            got: "\(expected != nil && actual == expected)")
                    }
                }
                for (source, target) in [
                    ("Canada", "China"), ("SFO", "CDG"), ("Tokyo", "SF"), ("SF", "Tokyo"),
                    ("New York", "São Paulo"), ("Kolkata", "Kathmandu"), ("Kiritimati", "Pago Pago")
                ] {
                    let expected = CalcEngine.evaluate(
                        "time \(source) to \(target)", now: now, calendar: calendar)
                    for phrase in ["time", "timezone", "time zone"] {
                        let query = "\(source) \(phrase) to \(target)"
                        let actual = CalcEngine.evaluate(query, now: now, calendar: calendar)
                        check(
                            "\(query) [\(home), \(now)]", expected: "true",
                            got: "\(expected != nil && actual == expected)")
                    }
                }
            }
        }
        for query in [
            "Screen Time", "QuickTime Player", "Time Machine", "FaceTime", "PSTT time", "xyzzy time",
            "SF junk time", "4 hours time", "90 min time", "5pm time", "5pm SF time",
            "SF current time", "SF time now", "SF time + 2h", "time in SF time", "time time"
        ] {
            expectNilAt(query)
        }
        for place in ["PSTT", "xyzzy", "SF junk", "4 hours", "5pm SF", "time"] {
            for query in [
                "time \(place)", "\(place) timezone", "\(place) time zone",
                "timezone \(place)", "timezone in \(place)", "\(place) time to China",
                "\(place) timezone to China", "Canada time zone to \(place)"
            ] {
                expectNilAt(query)
            }
        }
        for query in [
            "timezone", "time zone", "timezone in", "timezone in in SF", "timezone to China",
            "timezone settings", "SF timezone app", "Canada time to",
            "Canada time to China to Tokyo", "time in SF in 4 hours", "now in usa in 2h",
            "Canada timezone to 2h", "timezone in 4 hours", "Canada time to China + 2h"
        ] {
            expectNilAt(query)
        }

        // 裸数字取其所处时刻隐含的单位
        expectDisplayAt("3:45pm + 5", "24 July at 8:45 PM")
        expectDisplayAt("3:45pm - 2", "24 July at 1:45 PM")
        expectDisplayAt("august 5 + 5", "10 August")
        expectDisplayAt("august 5 - 5", "31 July")

        // 具名时刻一旦带时间或限定词就出卡片
        expectDisplayAt("tomorrow at 9am", "25 July at 9:00 AM")
        expectDisplayAt("next monday", "27 July")
        expectDisplayAt("last friday", "17 July")
        expectBadgesAt("tomorrow at 9am", source: "Friday, 24 July", target: "Saturday")
        expectDisplayAt("next monday at 7:30 + 5", "27 July at 12:30 PM")
        expectDisplayAt("next monday at 7:30 + 1 day 2h 15min - 1", "28 July at 8:45 AM")
        expectDisplayAt("tomorrow at 23:30 + 1.5 hours", "26 July at 1:00 AM")
        expectDisplayAt("3 days from next monday at 7:30", "30 July at 7:30 AM")
        expectDisplayAt("1h 30min ago", "23 July at 10:48 PM")
        expectDisplayAt("31.1.26 at 7:30 + 1 month", "28 February at 7:30 AM")
        expectDisplayAt("29.2.24 + 1 year", "28 February, 2025")
        expectDisplayAt("today + 1 year 2 months - 1 day", "23 September, 2027")
        expectDisplayAt("1. jan + 1 + 1", "3 January")
        expectDisplayAt("hours till tomorrow at 7:30", "31.2 hours")
        expectDisplayAt("hours since yesterday at noon", "12.3 hours")
        expectDisplayAt("hours till friday at midnight", "167.7 hours")
        expectDisplayAt("hours since friday at midnight", "0.3 hours")
        expectDisplayAt("hours till jul 24 at midnight", "8,759.7 hours")
        expectDisplayAt("next monday at 9:30 - next monday at 7:00", "2 hr 30 min")
        expectDisplayAt("next monday at 9:30 - next monday at 7:00 to minutes", "150 min")
        expectDisplayAt("2026-08-01 - 2026-07-24", "8 days")
        expectDisplayAt("today at 9:30 - today at 7:00 to hours", "2.5 hr")
        expectDisplayAt("now + 5 seconds", "24 July at 12:18:05 AM")
        expectDisplayAt("next\u{a0}monday at\t7:30 + 5", "27 July at 12:30 PM")
        expectDisplayAt("tomorrow - 5 weekdays", "20 July")
        expectDisplayAt("today + 10000 weekdays", "21 November, 2064")
        for query in [
            "tomorrow at 7:99", "tomorrow at 7::30", "today + 1.5 months",
            "today + 1h 30", "today + -9223372036854775808 weekdays", "today + 9223372036854775807 weeks"
        ] {
            expectNilAt(query)
        }
        var vienna = clock.calendar
        vienna.timeZone = TimeZone(identifier: "Europe/Vienna")!
        expectDisplayAt("2026-03-28 at 7:30 + 1 day", "29 March at 7:30 AM", calendar: vienna)
        expectDisplayAt("2026-03-28 at 7:30 + 24 hours", "29 March at 8:30 AM", calendar: vienna)
        expectDisplayAt("2026-03-29 at 7:30 - 2026-03-28 at 7:30 to hours", "23 hr", calendar: vienna)
        expectDisplayAt("2026-10-24 at 7:30 + 1 day", "25 October at 7:30 AM", calendar: vienna)
        expectDisplayAt("2026-10-25 at 7:30 - 2026-10-24 at 7:30 to hours", "25 hr", calendar: vienna)
        expectDisplayAt("1:00 - 3:00", "-2 hr", calendar: vienna)
        let springNow = clock.calendar.date(from: DateComponents(year: 2026, month: 3, day: 29))!
        expectNilAt("2:30am vienna in london", now: springNow, calendar: vienna)

        // 口语化的函数与运算符名称
        expectDisplay("square root of 625", "25")
        expectDisplay("square root of 64", "8")
        expectDisplay("cube root of 27", "3")
        expectDisplay("2 power 10", "1,024")
        expectDisplay("2 power 3 power 2", "512")

        // 工作日跳过周末。时钟为 2026-07-24 周五，因此每一跳都会跨过一个。
        expectDisplayAt("today + 1 business day", "27 July")
        expectDisplayAt("today + 5 business days", "31 July")
        expectDisplayAt("today - 1 business day", "23 July")
        expectDisplayAt("today - 3 business days", "21 July")
        expectDisplayAt("tomorrow + 10 work days", "7 August")
        expectDisplayAt("today + 15 workdays", "14 August")
        expectDisplayAt("today + 5 weekdays", "31 July")
        // 星期几挂在徽标上而不是日期上
        expectBadgesAt("today + 5 business days", source: "Friday, 24 July", target: "Friday")
        expectBadgesAt("today + 1 business day", source: "Friday, 24 July", target: "Monday")
        // 时长可以前置，由 `from` 指定锚点，或由 `ago` 隐含今天
        expectDisplayAt("5 weekdays from now", "31 July")
        expectDisplayAt("10 business days from today", "7 August")
        expectDisplayAt("3 days from today", "27 July")
        expectDisplayAt("2 weeks ago", "10 July")
        expectDisplayAt("3 days ago", "21 July")
        expectBadgesAt("5 weekdays from now", source: "Friday, 24 July", target: "Friday")
        // 同时带日和年的月份名
        expectDisplayAt("august 26 2026 + 15 workdays", "16 September")
        expectDisplayAt("august 26 2026 + 15 days", "10 September")
        expectDisplayAt("26 august 2026 + 1 day", "27 August")
        expectDisplayAt("august 26 2027 + 1 day", "27 August, 2027")
        // 8 小时单位是另一回事，仍按原样作答
        expectDisplay("55h in workdays", "6.875 workdays")
        expectDisplay("3 workdays in hours", "24 hr")
        expectNil("5 from 10")

        // 表达式中间的换算，过去需要加括号
        expectDisplay("10kg to lb + 3lb", "25.04622622 lb")
        expectDisplay("10kg to lb - 1lb", "21.04622622 lb")
        expectDisplay("100 km/h to mph + 3mph", "65.13711922 mph")
        expectDisplay("10km to mi + 3mi", "9.213711922 mi")
        expectDisplay("10kg to lb + 3lb + 1lb", "26.04622622 lb")
        expectDisplay("10km to mi + 3mi to km", "14.828032 km")
        expectDisplay("10kg to lb + 3", "25.04622622 lb")
        expectError("1kg to m + 3", "Cannot convert Weight to Length.")
        // 尾随的 `to` 仍换算整个表达式，而不是最后一个操作数
        expectDisplay("10kg + 500g to lb", "23.14853753 lb")
        expectDisplay("1kg + 1kg to g", "2,000 g")
        expectDisplay("2hr + 30min to min", "150 min")

        localeTests()
        chainTests()

        print("\n\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - 区域感知（locale）的输入与输出

    /// 测试用的数字格式：意大利（小数逗号、点分组）、法语（窄不换行空格分组）、瑞士（点小数、撇号分组）与无分组格式。
    static let italian = CalcNumberFormat(decimalSeparator: ",", groupingSeparator: ".")!
    static let french = CalcNumberFormat(decimalSeparator: ",", groupingSeparator: "\u{202F}")!
    static let swiss = CalcNumberFormat(decimalSeparator: ".", groupingSeparator: "\u{2019}")!
    static let ungrouped = CalcNumberFormat(decimalSeparator: ",", groupingSeparator: nil)!

    /// 验证区域感知的数字格式：格式解析、输入与输出、函数参数分隔符，以及不应被数字重写的日期/时钟/时区。
    static func localeTests() {
        // 从 Mac 的分隔符解析出格式
        check(
            "format [en separators]", expected: "true",
            got: "\(CalcNumberFormat(decimalSeparator: ".", groupingSeparator: ",") == .english)")
        check(
            "format [arabic decimal]", expected: "nil",
            got: "\(CalcNumberFormat(decimalSeparator: "\u{066B}", groupingSeparator: "\u{066C}") as Any)")
        check(
            "format [grouping equal to decimal]", expected: "nil",
            got:
                "\(CalcNumberFormat(decimalSeparator: ",", groupingSeparator: ",")?.groupingSeparator as Any)"
        )
        check(
            "format [ascii space grouping]", expected: "nil",
            got:
                "\(CalcNumberFormat(decimalSeparator: ",", groupingSeparator: " ")?.groupingSeparator as Any)"
        )
        check("format [it argument separator]", expected: ";", got: String(italian.argumentSeparator))
        check("format [ch argument separator]", expected: ",", got: String(swiss.argumentSeparator))

        // issue 中的示例本身
        expectLocalized("2,3 + 1,5", "3,8", italian)
        expectLocalized("1.234,56 + 0,44", "1.235", italian)
        expectLocalized("10/4", "2,5", italian)
        expectLocalizedCopy("1.234,56 + 0,44", "1235", italian)
        expectLocalizedCopy("10/4", "2,5", italian)

        // 小数逗号、点分组
        expectLocalized("2^20", "1.048.576", italian)
        expectLocalized("1.000.000 / 3", "333.333,3333", italian)
        expectLocalized("1/3", "0,3333333333", italian)
        expectLocalized(",5 + 1", "1,5", italian)
        expectLocalized("1,5e3", "1.500", italian)
        expectLocalized("2,5k", "2.500", italian)
        expectLocalized("12.345.678 + 1", "12.345.679", italian)
        expectLocalized("-1.234,5 * 2", "-2.469", italian)
        expectLocalized("2 + 2 =", "4", italian)
        expectLocalizedCopy("2^20", "1048576", italian)
        expectLocalizedCopy("1/3", "0,3333333333", italian)

        // 函数参数使用 `;`；数字之间的逗号始终是小数点
        expectLocalized("max(2,5; 3)", "3", italian)
        expectLocalized("max(2,5;3,5)", "3,5", italian)
        expectLocalized("hypot(3;4)", "5", italian)
        expectLocalized("round(3,14159; 2)", "3,14", italian)
        expectLocalized("gcd(12;18;8)", "2", italian)
        expectLocalized("log(8;2)", "3", italian)
        expectLocalized("max(1.000; 999)", "1.000", italian)
        expectLocalized("max(2,3)", "2,3", italian)
        expectLocalized("hypot(3m;400cm)", "5 m", italian)
        expectLocalizedExpression("hypot(3m;400cm)", "hypot(3 m; 400 cm)", italian)
        expectLocalizedExpression("max(2,5;3)", "max(2,5; 3)", italian)
        // 带空格的逗号不可能位于两个数字之间，因此仍作分隔
        expectLocalized("max(2, 3)", "3", italian)
        expectLocalized("average of 10; 20; 30", "20", italian)
        expectLocalized("average of 10, 20, 30", "20", italian)
        expectLocalized("sum of 1,5; 2,5", "4", italian)

        // 无法唯一解读的数字不出卡片，而不是猜测
        expectLocalizedNil("1,2,3", italian)
        expectLocalizedNil("1.5 + 1", italian)
        expectLocalizedNil("1.23,4 + 1", italian)
        expectLocalizedNil("1,234.5 + 1", italian)
        expectLocalizedNil("12.34 * 2", italian)
        expectLocalizedNil("1.2345 + 1", italian)

        // 后续数字还在输入时，部分输入仍保留卡片
        expectLocalized("1 + 2,", "3", italian)
        expectLocalized("2,5 +", "2,5", italian)
        expectLocalizedExpression("2,5 +", "2,5 +", italian)
        expectLocalizedExpression("1.234,5 *", "1234,5 ×", italian)

        // 单位、货币和百分比由同一个格式化器渲染
        expectLocalized("1,5km to m", "1.500 m", italian)
        expectLocalized("10kg + 500g", "10.500 g", italian)
        expectLocalized("2,5 hours to min", "150 min", italian)
        expectLocalized("5feet + 1m", "2,524 m", italian)
        expectLocalizedCopy("1,5km to m", "1500 m", italian)
        expectLocalized("€1.234,50 to usd", "1.341,85 USD", italian)
        expectLocalizedCopy("€1.234,50 to usd", "1341,85 USD", italian)
        expectLocalized("$10 + 5", "15,00 USD", italian)
        expectLocalized("20% off 1.500", "1.200", italian)
        expectLocalized("0x1000", "4.096", italian)
        expectLocalized("255 to hex", "0xFF", italian)
        expectLocalizedCopy("0x1000", "4096", italian)
        expectLocalizedExpression("1,5km to m", "1,5 km", italian)

        // 日期、时钟和时区永远不会进入数字重写
        for query in [
            "17.2.26 + 100 weekdays", "25.8.27", "25. aug", "25. aug + 3",
            "time in Tokyo", "1970-01-01T00:00:00.125Z to unix ms", "1.2.3 + 1", "7:30 - 13:30"
        ] {
            expectSameAsEnglish(query, italian)
        }
        expectLocalized("1970-01-01T00:00:00Z + 1h to unix", "3.600", italian)
        expectLocalized("hrs till 9am", "8,7 hours", italian)

        // 空格分组：使用 Mac 的窄不换行空格，绝不是输入的空格
        expectLocalized("1\u{202F}234,5 + 0,5", "1\u{202F}235", french)
        expectLocalized("2^20", "1\u{202F}048\u{202F}576", french)
        expectLocalized("max(1,5; 2)", "2", french)
        expectLocalized("1.5 + 1", "2,5", french)

        // 小数点为点、分组为撇号时，逗号留给参数
        expectLocalized("1\u{2019}234.5 + 0.5", "1\u{2019}235", swiss)
        expectLocalized("max(1,2)", "2", swiss)
        expectLocalized("1,000 + 234", "1\u{2019}234", swiss)
        expectLocalized("10/4", "2.5", swiss)
        expectSameAsEnglish("19.2.27", swiss)
        expectSameAsEnglish("1.2.3 + 1", swiss)

        // 不带分组的格式既不读取也不写出分组
        expectLocalized("1234,5 * 2", "2469", ungrouped)
        expectLocalized("2^20", "1048576", ungrouped)
        expectLocalized("1.234 + 1", "2,234", ungrouped)

        // 英文保持逐字节不变
        expectLocalized("1,000 + 234", "1,234", .english)
        expectLocalized("max(2,3)", "3", .english)
        expectLocalizedNil("max(2;3)", .english)

        // 规范历史文本，为显示而本地化
        check("history [grouped]", expected: "1.234,5 kg", got: italian.localized("1,234.5 kg"))
        check("history [dotted date]", expected: "19.2.27", got: italian.localized("19.2.27"))
        check("history [clock]", expected: "00:18:00.123", got: italian.localized("00:18:00.123"))
        check(
            "history [date prose]", expected: "Friday, 24 July 2026",
            got: italian.localized("Friday, 24 July 2026"))
        check(
            "history [arguments]", expected: "max(1,5; 2)",
            got: italian.localizedExpression("max(1.5, 2)"))
        // 在调用内部，规范逗号是参数，即使看起来像分组
        check(
            "history [unspaced arguments]", expected: "max(2;3)", got: italian.localizedExpression("max(2,3)")
        )
        check(
            "history [grouping-shaped argument]", expected: "max(1;234) + 1.234",
            got: italian.localizedExpression("max(1,234) + 1,234"))
        check(
            "history [decimal argument]", expected: "round(3,14159;2)",
            got: italian.localizedExpression("round(3.14159,2)"))
        check(
            "history [nested call]", expected: "2max(1; min(2;3))",
            got: italian.localizedExpression("2max(1, min(2,3))"))
        check("history [ch arguments]", expected: "max(1,234)", got: swiss.localizedExpression("max(1,234)"))
        expectLocalizedExpression("max(1,234)", "max(1,234)", swiss)
        expectLocalized("max(1;234)", "234", italian)
        check("history [exponent]", expected: "1,524157875e+16", got: italian.localized("1.524157875e+16"))
        check("history [english]", expected: "1,234.5", got: CalcNumberFormat.english.localized("1,234.5"))
        check("history [search]", expected: "3.8", got: italian.canonical("3,8") ?? "nil")
    }

    /// 验证 CalcResult.canChain：可继续运算的结果应可链式，瞬时/不可链式结果应为 false。
    static func chainTests() {
        for query in [
            "2^10", "1/3", "100 usd to eur", "10 km to mi", "1m", "255 to hex", "145 mins to timespan",
            "20% off 500", "2^10 +"
        ] {
            check(query + " [chains]", expected: "true", got: chains(evaluate(query)))
        }
        for query in [
            "now + 90 min", "now + 90 min +", "today", "time", "time in Tokyo", "3pm London in Tokyo",
            "5 > 3",
            "ratio of 1920 to 1080"
        ] {
            check(query + " [chains]", expected: "false", got: chains(evaluate(query)))
        }
        check(
            "now + 90 min [chains, localized]", expected: "false",
            got: chains(evaluateLocalized("now + 90 min", italian)))
    }

    /// 用固定时钟与固定汇率对英文格式求值。
    static func evaluate(_ query: String) -> CalcResult? {
        CalcEngine.evaluate(query, now: clock.now, calendar: clock.calendar, rates: fx)
    }

    /// 以字符串形式回报结果是否可链式，nil 结果返回 "nil"。
    static func chains(_ result: CalcResult?) -> String {
        result.map { "\($0.canChain)" } ?? "nil"
    }

    /// 用指定数字格式求值，并把结果本地化后再返回。
    static func evaluateLocalized(_ query: String, _ format: CalcNumberFormat) -> CalcResult? {
        CalcEngine.evaluate(
            query, now: clock.now, calendar: clock.calendar, rates: fx, format: format
        ).map(format.localized)
    }

    /// 生成断言失败时的可读标签，带上所用的小数分隔符。
    static func formatLabel(_ query: String, _ format: CalcNumberFormat) -> String {
        "\(query) [decimal \(format.decimalSeparator)]"
    }

    /// 断言本地化后的显示文本；若结果为 nil / 错误则计为失败。
    static func expectLocalized(_ query: String, _ expected: String, _ format: CalcNumberFormat) {
        guard case .value(let display, _)? = evaluateLocalized(query, format)?.payload else {
            fail(formatLabel(query, format), expected: expected, got: "nil / error")
            return
        }
        check(formatLabel(query, format), expected: expected, got: display)
    }

    /// 断言本地化后的复制文本。
    static func expectLocalizedCopy(_ query: String, _ expected: String, _ format: CalcNumberFormat) {
        guard case .value(_, let copy)? = evaluateLocalized(query, format)?.payload else {
            fail(formatLabel(query, format), expected: expected, got: "nil / error")
            return
        }
        check(formatLabel(query, format) + " [copy]", expected: expected, got: copy)
    }

    /// 断言本地化后的表达式回显。
    static func expectLocalizedExpression(
        _ query: String, _ expected: String, _ format: CalcNumberFormat
    ) {
        guard let result = evaluateLocalized(query, format) else {
            fail(formatLabel(query, format), expected: expected, got: "nil")
            return
        }
        check(formatLabel(query, format) + " [expression]", expected: expected, got: result.expression)
    }

    /// 断言该查询在指定格式下不出卡片。
    static func expectLocalizedNil(_ query: String, _ format: CalcNumberFormat) {
        if let result = evaluateLocalized(query, format) {
            fail(formatLabel(query, format), expected: "nil", got: "\(result.payload)")
        } else {
            passes += 1
        }
    }

    /// 不含小数的文本必须与英文渲染结果完全一致。
    static func expectSameAsEnglish(_ query: String, _ format: CalcNumberFormat) {
        let english = CalcEngine.evaluate(query, now: clock.now, calendar: clock.calendar, rates: fx)
        check(
            formatLabel(query, format) + " [same as English]", expected: "\(english as Any)",
            got: "\(evaluateLocalized(query, format) as Any)")
    }

    // MARK: - 用于确定性日期/时间测试的固定时钟（2026-07-24 周五 00:18:00 UTC）

    static let clock: (now: Date, calendar: Calendar) = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 24
        components.hour = 0
        components.minute = 18
        components.second = 0
        return (calendar.date(from: components)!, calendar)
    }()

    // MARK: - 固定汇率，使货币答案确定

    /// 故意缺失：被识别的代码必须走到 "no exchange rate"，而不是不出卡片。
    static let fx = CurrencyRates(
        base: "USD",
        rates: [
            "USD": 1, "EUR": 0.92, "GBP": 0.79, "JPY": 157, "INR": 83.5, "CAD": 1.36,
            "KRW": 1330, "IDR": 18053, "CHF": 0.81, "AED": 3.6725, "SGD": 1.35,
            "BTC": 1.0 / 60_000, "ETH": 1.0 / 2_000, "SOL": 1.0 / 100, "DOGE": 10
        ],
        fetchedAt: Date(timeIntervalSince1970: 1_785_000_000))

    /// 基准不是源货币的配对，以及无意义的汇率，两者都必须被丢弃。
    static let fiatJSON = Data(
        #"{"success":true,"source":"USD","quotes":{"USDEUR":0.9,"EURGBP":0.8,"USDBAD":-1}}"#.utf8)
    /// 以相反方向报价 —— 1 BTC 价值 20,000 USD，因此表中存 0.00005。
    static let cryptoJSON = Data(#"{"success":true,"target":"USD","rates":{"BTC":20000}}"#.utf8)

    // MARK: - 辅助函数

    /// 在可注入时钟（默认固定时钟）下断言显示文本，用于日期/时间用例。
    static func expectDisplayAt(
        _ query: String, _ expected: String, now: Date = clock.now, calendar: Calendar? = nil
    ) {
        guard
            case .value(let display, _)? = CalcEngine.evaluate(
                query, now: now, calendar: calendar ?? clock.calendar)?.payload
        else {
            fail(query, expected: expected, got: "nil / error")
            return
        }
        check(query, expected: expected, got: display)
    }

    /// 在可注入时钟下断言源/目标徽标。
    static func expectBadgesAt(
        _ query: String, source: String, target: String, now: Date = clock.now,
        calendar: Calendar? = nil
    ) {
        guard let result = CalcEngine.evaluate(query, now: now, calendar: calendar ?? clock.calendar)
        else {
            fail(query, expected: "\(source) → \(target)", got: "nil")
            return
        }
        check(query + " [source badge]", expected: source, got: result.sourceBadge ?? "nil")
        check(query + " [target badge]", expected: target, got: result.targetBadge ?? "nil")
    }

    /// 在可注入时钟下断言该查询不出卡片。
    static func expectNilAt(_ query: String, now: Date = clock.now, calendar: Calendar? = nil) {
        if let result = CalcEngine.evaluate(query, now: now, calendar: calendar ?? clock.calendar) {
            fail(query, expected: "nil", got: "\(result.payload)")
        } else {
            passes += 1
        }
    }

    /// 区域货币是注入的，因此测试套件忽略宿主机的区域。
    /// 给断言消息加上区域标签，便于定位注入区域导致的差异。
    static func label(_ query: String, _ region: String?) -> String {
        region.map { "\(query) [region \($0)]" } ?? query
    }

    /// 断言源/目标徽标，可附带注入的区域货币。
    static func expectBadges(
        _ query: String, source: String, target: String, region: String? = nil
    ) {
        guard
            let result = CalcEngine.evaluate(
                query, now: clock.now, calendar: clock.calendar, rates: fx, region: region)
        else {
            fail(label(query, region), expected: "\(source) → \(target)", got: "nil")
            return
        }
        check(
            label(query, region) + " [source badge]", expected: source,
            got: result.sourceBadge ?? "nil")
        check(
            label(query, region) + " [target badge]", expected: target,
            got: result.targetBadge ?? "nil")
    }

    /// 断言显示文本（带分组），可附带注入的区域货币。
    static func expectDisplay(_ query: String, _ expected: String, region: String? = nil) {
        guard
            case .value(let display, _)? = CalcEngine.evaluate(
                query, now: clock.now, calendar: clock.calendar, rates: fx, region: region)?.payload
        else {
            fail(label(query, region), expected: expected, got: "nil / error")
            return
        }
        check(label(query, region), expected: expected, got: display)
    }

    /// 断言复制文本（纯文本），可附带注入的区域货币。
    static func expectCopy(_ query: String, _ expected: String, region: String? = nil) {
        guard
            case .value(_, let copy)? = CalcEngine.evaluate(
                query, now: clock.now, calendar: clock.calendar, rates: fx, region: region)?.payload
        else {
            fail(label(query, region), expected: expected, got: "nil / error")
            return
        }
        check(label(query, region), expected: expected, got: copy)
    }

    /// 断言求值结果为携带预期文案的 error 载荷。
    static func expectError(_ query: String, _ expected: String) {
        guard
            case .error(let message)? = CalcEngine.evaluate(
                query, now: clock.now, calendar: clock.calendar, rates: fx)?.payload
        else {
            fail(query, expected: "error: \(expected)", got: "nil / value")
            return
        }
        check(query, expected: expected, got: message)
    }

    /// 尚无快照落地 —— 首次运行，或仍处于离线。
    /// 断言在无汇率快照时给出预期的错误文案。
    static func expectErrorWithoutRates(_ query: String, _ expected: String) {
        guard
            case .error(let message)? = CalcEngine.evaluate(
                query, now: clock.now, calendar: clock.calendar, rates: nil)?.payload
        else {
            fail(query, expected: "error: \(expected)", got: "nil / value")
            return
        }
        check(query, expected: expected, got: message)
    }

    /// 断言结果的表达式回显文本。
    static func expectExpression(_ query: String, _ expected: String, region: String? = nil) {
        guard
            let result = CalcEngine.evaluate(
                query, now: clock.now, calendar: clock.calendar, rates: fx, region: region)
        else {
            fail(label(query, region), expected: expected, got: "nil")
            return
        }
        check(label(query, region), expected: expected, got: result.expression)
    }

    /// `CurrencyFeed` 接收的两个载荷与 store 收到的完全一致。
    /// 断言快照解码结果，按 USD / EUR / BTC 速率与 complete 标记汇总比对。
    static func expectSnapshot(_ name: String, fiat: Data, crypto: Data?, expected: String) {
        guard let result = try? CurrencyFeed.snapshot(fiat: fiat, crypto: crypto, now: clock.now)
        else {
            fail(name, expected: expected, got: "threw")
            return
        }
        let show = { (code: String) in result.rates.rates[code].map(CalcFormatter.copyText) ?? "nil" }
        check(
            name, expected: expected,
            got: "USD=\(show("USD")) EUR=\(show("EUR")) BTC=\(show("BTC")) "
                + "complete=\(result.complete)")
    }

    /// 断言快照解码会抛出错误（例如响应里没有任何报价）。
    static func expectSnapshotThrows(_ name: String, fiat: Data) {
        if let result = try? CurrencyFeed.snapshot(fiat: fiat, crypto: nil, now: clock.now) {
            fail(name, expected: "throws", got: "\(result.rates.rates.count) rates")
        } else {
            passes += 1
        }
    }

    /// 断言该查询不出卡片，可附带注入的区域货币。
    static func expectNil(_ query: String, region: String? = nil) {
        if let result = CalcEngine.evaluate(
            query, now: clock.now, calendar: clock.calendar, rates: fx, region: region)
        {
            fail(label(query, region), expected: "nil", got: "\(result.payload)")
        } else {
            passes += 1
        }
    }

    /// 比较实际值与预期字符串，相等则计入通过数，否则记录失败。
    static func check(_ query: String, expected: String, got: String) {
        if got == expected {
            passes += 1
        } else {
            fail(query, expected: expected, got: got)
        }
    }

    /// 记录一次失败并打印查询、预期与实际值。
    static func fail(_ query: String, expected: String, got: String) {
        failures += 1
        print("FAIL  \(query)\n      expected: \(expected)\n      got:      \(got)")
    }
}
