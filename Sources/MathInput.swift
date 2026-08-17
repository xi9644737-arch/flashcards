import Foundation

/// 手机上打数学公式的辅助。
/// 思路：让你用键盘上打得出来的写法（a_n、q^(n-1)、sqrt、>=），
/// 一键换成真正的符号（aₙ、q⁽ⁿ⁻¹⁾、√、≥）。
/// 不做自动转换——边打边变会跟你抢输入框，改成手动按一下。
enum MathInput {

    private static let subs: [Character: Character] = [
        "0":"₀","1":"₁","2":"₂","3":"₃","4":"₄","5":"₅","6":"₆","7":"₇","8":"₈","9":"₉",
        "+":"₊","-":"₋","=":"₌","(":"₍",")":"₎",
        "a":"ₐ","e":"ₑ","h":"ₕ","i":"ᵢ","j":"ⱼ","k":"ₖ","l":"ₗ","m":"ₘ","n":"ₙ",
        "o":"ₒ","p":"ₚ","r":"ᵣ","s":"ₛ","t":"ₜ","u":"ᵤ","v":"ᵥ","x":"ₓ"
    ]

    private static let sups: [Character: Character] = [
        "0":"⁰","1":"¹","2":"²","3":"³","4":"⁴","5":"⁵","6":"⁶","7":"⁷","8":"⁸","9":"⁹",
        "+":"⁺","-":"⁻","=":"⁼","(":"⁽",")":"⁾",
        "a":"ᵃ","b":"ᵇ","c":"ᶜ","d":"ᵈ","e":"ᵉ","f":"ᶠ","g":"ᵍ","h":"ʰ","i":"ⁱ","j":"ʲ",
        "k":"ᵏ","l":"ˡ","m":"ᵐ","n":"ⁿ","o":"ᵒ","p":"ᵖ","r":"ʳ","s":"ˢ","t":"ᵗ",
        "u":"ᵘ","v":"ᵛ","w":"ʷ","x":"ˣ","y":"ʸ","z":"ᶻ"
    ]

    /// 整词替换。放在上下标处理之前跑
    private static let words: [(String, String)] = [
        ("sqrt", "√"), ("Sqrt", "√"),
        (">=", "≥"), ("<=", "≤"), ("!=", "≠"), ("+-", "±"),
        ("->", "→"), ("=>", "⇒"), ("<=>", "⇔"),
        ("inf", "∞"), ("deg", "°"),
        ("alpha", "α"), ("beta", "β"), ("theta", "θ"), ("pi", "π"),
        ("Delta", "Δ"), ("delta", "δ"), ("Sigma", "Σ"), ("sigma", "σ"),
        ("cap", "∩"), ("cup", "∪"), ("subset", "⊆"), ("belong", "∈"),
        ("int", "∫"), ("sum", "Σ"),
    ]

    /// 把 a_n、q^(n-1)、sqrt、>= 这类写法展开成真符号
    static func expand(_ input: String) -> String {
        var s = input
        for (from, to) in words {
            s = s.replacingOccurrences(of: from, with: to)
        }

        var out = ""
        var chars = Array(s)
        var i = 0

        while i < chars.count {
            let c = chars[i]
            if c == "_" || c == "^" {
                let table = (c == "_") ? subs : sups
                let next = i + 1
                guard next < chars.count else { out.append(c); i += 1; continue }

                if chars[next] == "(" {
                    // 括号形式：q^(n-1) → q⁽ⁿ⁻¹⁾，括号本身也转成上下标括号
                    var j = next
                    var converted = ""
                    var ok = true
                    var closed = false
                    while j < chars.count {
                        let ch = chars[j]
                        if let mapped = table[Character(ch.lowercased())] ?? table[ch] {
                            converted.append(mapped)
                        } else {
                            ok = false; break
                        }
                        if ch == ")" { closed = true; j += 1; break }
                        j += 1
                    }
                    if ok && closed {
                        out += converted
                        i = j
                        continue
                    }
                    out.append(c); i += 1
                } else {
                    // 单字符形式：a_n → aₙ
                    let ch = chars[next]
                    if let mapped = table[Character(ch.lowercased())] ?? table[ch] {
                        out.append(mapped)
                        i = next + 1
                        continue
                    }
                    out.append(c); i += 1
                }
            } else {
                out.append(c)
                i += 1
            }
        }
        return out
    }

    /// 给编辑框用的速查提示
    static let cheatsheet = """
    a_n → aₙ　　a_1 → a₁
    q^2 → q²　　q^(n-1) → q⁽ⁿ⁻¹⁾
    sqrt → √　　>= → ≥　　!= → ≠
    pi → π　　theta → θ　　cap → ∩
    """
}
