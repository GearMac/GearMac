// 文件职责：维护渲染器支持的 LaTeX 名称到 Unicode 字符、原子类型与间距的对照表，并提供数学字母表样式映射。
// 分层：Model；不 import AppKit/SwiftUI，仅提供纯函数与静态数据，无副作用。
import Foundation

/// 本渲染器已知的 LaTeX 名称，每项包含它所绘制的字符以及 TeX 的间距类型。
enum MathSymbolCatalog {
    /// 符号条目：绘制的字符与 TeX 原子类型。
    typealias Symbol = (character: String, kind: MathNode.Kind)

    /// 按 LaTeX 名称查找符号及其原子类型，未收录时返回 nil。
    static func symbol(named name: String) -> Symbol? {
        if let character = greek[name] { return (character, .ord) }
        if let character = ordinary[name] { return (character, .ord) }
        if let character = binary[name] { return (character, .bin) }
        if let character = relations[name] { return (character, .rel) }
        if let character = opening[name] { return (character, .open) }
        if let character = closing[name] { return (character, .close) }
        return punctuation[name].map { ($0, .punct) }
    }

    /// 直接键入源码的字符，按其具名等价符号的方式处理间距。
    static func kind(of character: Character) -> MathNode.Kind {
        switch character {
        case "+", "-", "*": .bin
        case "=", "<", ">", ":": .rel
        case ",", ";": .punct
        case "(", "[": .open
        case ")", "]", "!", "?": .close
        default: typedKinds[String(character)] ?? .ord
        }
    }

    /// ASCII 字符实际绘制成的形式：TeX 的减号是 U+2212，其 `*` 是居中的星号。
    static func drawn(_ character: Character) -> String {
        switch character {
        case "-": "\u{2212}"
        case "*": "\u{2217}"
        case "'": "\u{2032}"
        default: String(character)
        }
    }

    /// 把字母或数字映射到某个 Unicode 数学字母表，STIX Two Math 可完整绘制这些字形。
    static func styled(_ character: Character, in alphabet: MathNode.Alphabet) -> String {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1
        else { return String(character) }
        let value = scalar.value
        if let exception = alphabetExceptions[alphabet]?[character] {
            return String(exception)
        }
        let start: (upper: UInt32?, lower: UInt32?, digit: UInt32?, greek: UInt32?) =
            switch alphabet {
            case .italic: (0x1D434, 0x1D44E, nil, 0x1D6FC)
            case .upright: (nil, nil, nil, nil)
            case .bold: (0x1D400, 0x1D41A, 0x1D7CE, 0x1D6C2)
            case .boldItalic: (0x1D468, 0x1D482, 0x1D7CE, 0x1D736)
            case .doubleStruck: (0x1D538, 0x1D552, 0x1D7D8, nil)
            case .script: (0x1D49C, 0x1D4B6, nil, nil)
            case .fraktur: (0x1D504, 0x1D51E, nil, nil)
            case .sansSerif: (0x1D5A0, 0x1D5BA, 0x1D7E2, nil)
            case .monospace: (0x1D670, 0x1D68A, 0x1D7F6, nil)
            }
        let mapped: UInt32? =
            switch value {
            case 0x41...0x5A: start.upper.map { $0 + value - 0x41 }
            case 0x61...0x7A: start.lower.map { $0 + value - 0x61 }
            case 0x30...0x39: start.digit.map { $0 + value - 0x30 }
            case 0x3B1...0x3C9: start.greek.map { $0 + value - 0x3B1 }
            default: nil
            }
        return mapped.flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? String(character)
    }

    /// Unicode 在数学区块之前就已编码的字母，因此在数学区块中这些位置是空缺。
    private static let alphabetExceptions: [MathNode.Alphabet: [Character: Character]] = [
        .italic: ["h": "ℎ", "ϵ": "𝜖", "ϑ": "𝜗", "ϰ": "𝜘", "ϕ": "𝜙", "ϱ": "𝜚", "ϖ": "𝜛"],
        .doubleStruck: ["C": "ℂ", "H": "ℍ", "N": "ℕ", "P": "ℙ", "Q": "ℚ", "R": "ℝ", "Z": "ℤ"],
        .script: [
            "B": "ℬ", "E": "ℰ", "F": "ℱ", "H": "ℋ", "I": "ℐ", "L": "ℒ", "M": "ℳ", "R": "ℛ", "e": "ℯ",
            "g": "ℊ", "o": "ℴ"
        ],
        .fraktur: ["C": "ℭ", "H": "ℌ", "I": "ℑ", "R": "ℜ", "Z": "ℨ"]
    ]

    /// 大运算符名称到绘制字符及上下限摆放方式的映射。
    static let largeOperators: [String: (character: String, limits: Bool)] = [
        "sum": ("∑", true), "prod": ("∏", true), "coprod": ("∐", true),
        "int": ("∫", false), "iint": ("∬", false), "iiint": ("∭", false), "oint": ("∮", false),
        "oiint": ("∯", false), "bigcup": ("⋃", true), "bigcap": ("⋂", true),
        "bigsqcup": ("⨆", true), "bigvee": ("⋁", true), "bigwedge": ("⋀", true),
        "bigoplus": ("⨁", true), "bigotimes": ("⨂", true), "bigodot": ("⨀", true),
        "biguplus": ("⨄", true)
    ]

    /// 直立的运算符名；`true` 表示在 display 样式下将其脚本放在上下方。
    static let functions: [String: (text: String, limits: Bool)] = [
        "arccos": ("arccos", false), "arcsin": ("arcsin", false), "arctan": ("arctan", false),
        "arg": ("arg", false), "cos": ("cos", false), "cosh": ("cosh", false), "cot": ("cot", false),
        "coth": ("coth", false), "csc": ("csc", false), "deg": ("deg", false), "det": ("det", true),
        "dim": ("dim", false), "exp": ("exp", false), "gcd": ("gcd", true), "hom": ("hom", false),
        "inf": ("inf", true), "ker": ("ker", false), "lg": ("lg", false), "lim": ("lim", true),
        "liminf": ("lim inf", true), "limsup": ("lim sup", true), "ln": ("ln", false),
        "log": ("log", false), "max": ("max", true), "min": ("min", true), "Pr": ("Pr", true),
        "sec": ("sec", false), "sin": ("sin", false), "sinh": ("sinh", false), "sup": ("sup", true),
        "tan": ("tan", false), "tanh": ("tanh", false), "argmax": ("arg max", true),
        "argmin": ("arg min", true)
    ]

    /// 除普通的 `( ) [ ] | / .` 字符之外，`\left`、`\right` 与 `\big` 还接受的定界符名称。
    static let delimiters: [String: String] = [
        "{": "{", "}": "}", "lbrace": "{", "rbrace": "}", "langle": "⟨", "rangle": "⟩",
        "lvert": "|", "rvert": "|", "vert": "|", "|": "‖", "Vert": "‖", "lVert": "‖", "rVert": "‖",
        "lfloor": "⌊", "rfloor": "⌋", "lceil": "⌈", "rceil": "⌉", "backslash": "\\",
        "uparrow": "↑", "downarrow": "↓", "updownarrow": "↕", "Uparrow": "⇑", "Downarrow": "⇓"
    ]

    /// 叠加到基上的组合标记；`true` 表示使用字体更宽的变体以覆盖整个基。
    static let accents: [String: (mark: String, wide: Bool)] = [
        "hat": ("\u{0302}", false), "widehat": ("\u{0302}", true), "check": ("\u{030C}", false),
        "tilde": ("\u{0303}", false), "widetilde": ("\u{0303}", true), "acute": ("\u{0301}", false),
        "grave": ("\u{0300}", false), "dot": ("\u{0307}", false), "ddot": ("\u{0308}", false),
        "dddot": ("\u{20DB}", false), "bar": ("\u{0304}", false), "breve": ("\u{0306}", false),
        "vec": ("\u{20D7}", false), "mathring": ("\u{030A}", false),
        "overrightarrow": ("\u{20D7}", true), "overleftarrow": ("\u{20D6}", true)
    ]

    /// 关系符前的 `\not`：在 Unicode 存在预组合否定形式时使用该字符。
    static let negations: [String: String] = [
        "=": "≠", "∈": "∉", "≡": "≢", "⊂": "⊄", "⊃": "⊅", "⊆": "⊈", "⊇": "⊉", "<": "≮", ">": "≯",
        "≤": "≰", "≥": "≱", "∼": "≁", "≈": "≉", "≅": "≇", "∣": "∤", "∥": "∦", "∋": "∌"
    ]

    /// 希腊字母名称到字符的映射。
    private static let greek: [String: String] = [
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ϵ", "varepsilon": "ε",
        "zeta": "ζ", "eta": "η", "theta": "θ", "vartheta": "ϑ", "iota": "ι", "kappa": "κ",
        "varkappa": "ϰ", "lambda": "λ", "mu": "μ", "nu": "ν", "xi": "ξ", "omicron": "ο", "pi": "π",
        "varpi": "ϖ", "rho": "ρ", "varrho": "ϱ", "sigma": "σ", "varsigma": "ς", "tau": "τ",
        "upsilon": "υ", "phi": "ϕ", "varphi": "φ", "chi": "χ", "psi": "ψ", "omega": "ω",
        "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ", "Xi": "Ξ", "Pi": "Π", "Sigma": "Σ",
        "Upsilon": "Υ", "Phi": "Φ", "Psi": "Ψ", "Omega": "Ω"
    ]

    /// 普通（ord）符号名称到字符的映射。
    private static let ordinary: [String: String] = [
        "infty": "∞", "partial": "∂", "nabla": "∇", "forall": "∀", "exists": "∃", "nexists": "∄",
        "emptyset": "∅", "varnothing": "∅", "aleph": "ℵ", "beth": "ℶ", "hbar": "ℏ", "ell": "ℓ",
        "Re": "ℜ", "Im": "ℑ", "wp": "℘", "imath": "𝚤", "jmath": "𝚥", "angle": "∠", "triangle": "△",
        "square": "□", "top": "⊤", "bot": "⊥", "neg": "¬", "lnot": "¬", "prime": "′",
        "degree": "°", "checkmark": "✓", "dagger": "†", "ddagger": "‡", "ldots": "…",
        "dots": "…", "cdots": "⋯", "vdots": "⋮", "ddots": "⋱", "flat": "♭", "sharp": "♯",
        "natural": "♮", "clubsuit": "♣", "diamondsuit": "♢", "heartsuit": "♡", "spadesuit": "♠",
        "vert": "|", "|": "‖", "Vert": "‖", "backslash": "\\", "#": "#", "&": "&", "%": "%",
        "$": "$", "_": "_", "surd": "√", "complement": "∁", "mho": "℧", "Box": "□"
    ]

    /// 二元运算符（bin）名称到字符的映射。
    private static let binary: [String: String] = [
        "pm": "±", "mp": "∓", "times": "×", "div": "÷", "cdot": "⋅", "ast": "∗", "star": "⋆",
        "circ": "∘", "bullet": "∙", "oplus": "⊕", "ominus": "⊖", "otimes": "⊗", "oslash": "⊘",
        "odot": "⊙", "cup": "∪", "cap": "∩", "sqcup": "⊔", "sqcap": "⊓", "vee": "∨", "lor": "∨",
        "wedge": "∧", "land": "∧", "setminus": "∖", "wr": "≀", "amalg": "⨿", "uplus": "⊎",
        "diamond": "⋄", "bigtriangleup": "△", "bigtriangledown": "▽", "triangleleft": "◁",
        "triangleright": "▷", "dotplus": "∔", "ltimes": "⋉", "rtimes": "⋊"
    ]

    /// 关系符（rel）名称到字符的映射。
    private static let relations: [String: String] = [
        "le": "≤", "leq": "≤", "ge": "≥", "geq": "≥", "leqslant": "⩽", "geqslant": "⩾", "ne": "≠",
        "neq": "≠", "equiv": "≡", "approx": "≈", "approxeq": "≊", "sim": "∼", "simeq": "≃",
        "cong": "≅", "propto": "∝", "ll": "≪", "gg": "≫", "prec": "≺", "succ": "≻",
        "preceq": "⪯", "succeq": "⪰", "in": "∈", "notin": "∉", "ni": "∋", "subset": "⊂",
        "supset": "⊃", "subseteq": "⊆", "supseteq": "⊇", "subsetneq": "⊊", "supsetneq": "⊋",
        "sqsubseteq": "⊑", "sqsupseteq": "⊒", "mid": "∣", "nmid": "∤", "parallel": "∥",
        "nparallel": "∦", "perp": "⟂", "models": "⊨", "vdash": "⊢", "dashv": "⊣", "asymp": "≍",
        "doteq": "≐", "lesssim": "≲", "gtrsim": "≳", "triangleq": "≜", "coloneqq": "≔",
        "therefore": "∴", "because": "∵", "to": "→", "rightarrow": "→", "leftarrow": "←",
        "gets": "←", "leftrightarrow": "↔", "Rightarrow": "⇒", "Leftarrow": "⇐",
        "Leftrightarrow": "⇔", "iff": "⟺", "implies": "⟹", "impliedby": "⟸",
        "longrightarrow": "⟶", "longleftarrow": "⟵", "longleftrightarrow": "⟷",
        "Longrightarrow": "⟹", "Longleftarrow": "⟸", "Longleftrightarrow": "⟺", "mapsto": "↦",
        "longmapsto": "⟼", "hookrightarrow": "↪", "hookleftarrow": "↩", "uparrow": "↑",
        "downarrow": "↓", "updownarrow": "↕", "Uparrow": "⇑", "Downarrow": "⇓", "nearrow": "↗",
        "searrow": "↘", "nwarrow": "↖", "swarrow": "↙", "rightleftharpoons": "⇌",
        "leftrightharpoons": "⇋", "leadsto": "⇝", "rightharpoonup": "⇀", "leftharpoonup": "↼",
        "bowtie": "⋈", "smile": "⌣", "frown": "⌢", "vDash": "⊨", "Vdash": "⊩", "nleq": "≰",
        "ngeq": "≱", "nsim": "≁", "ncong": "≇", "neqsim": "≂", "gtreqless": "⋛", "lesseqgtr": "⋚"
    ]

    /// 开界符（open）名称到字符的映射。
    private static let opening: [String: String] = [
        "{": "{", "lbrace": "{", "langle": "⟨", "lvert": "|", "lVert": "‖", "lfloor": "⌊",
        "lceil": "⌈"
    ]

    /// 闭界符（close）名称到字符的映射。
    private static let closing: [String: String] = [
        "}": "}", "rbrace": "}", "rangle": "⟩", "rvert": "|", "rVert": "‖", "rfloor": "⌋",
        "rceil": "⌉"
    ]

    /// 标点（punct）名称到字符的映射。
    private static let punctuation: [String: String] = ["colon": ":"]

    /// 以 Unicode 直接键入的关系符与运算符保持 TeX 的间距，如同 `≤` 与 `\le` 一样。
    private static let typedKinds: [String: MathNode.Kind] = {
        var kinds: [String: MathNode.Kind] = [:]
        for character in binary.values { kinds[character] = .bin }
        for character in relations.values { kinds[character] = .rel }
        for (character, _) in largeOperators.values { kinds[character] = .op }
        kinds["−"] = .bin
        return kinds
    }()
}
