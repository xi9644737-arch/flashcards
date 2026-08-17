import SwiftUI

// MARK: - 配色
//
// 暖纸底 + 陶土橙 + 衬线标题。浅色是米白不是纯白，深色是暖灰不是纯黑，
// 长时间盯着不刺眼。分割线用极淡的描边，不用系统那种硬线。

extension Color {
    init(hexLight: UInt32, hexDark: UInt32) {
        self.init(uiColor: UIColor { trait in
            let hex = trait.userInterfaceStyle == .dark ? hexDark : hexLight
            return UIColor(
                red:   CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue:  CGFloat(hex & 0xFF) / 255,
                alpha: 1)
        })
    }
}

enum T {
    /// 页面底色，暖米白 / 暖深灰
    static let bg       = Color(hexLight: 0xFAF9F5, hexDark: 0x262624)
    /// 卡片、分组的表面色
    static let surface  = Color(hexLight: 0xFFFFFF, hexDark: 0x30302E)
    /// 比表面再深一点，用于输入框
    static let sunken   = Color(hexLight: 0xF2F0EA, hexDark: 0x3A3A37)
    static let text     = Color(hexLight: 0x1F1E1D, hexDark: 0xF5F4EF)
    static let dim      = Color(hexLight: 0x6B6862, hexDark: 0xA6A29A)
    static let faint    = Color(hexLight: 0x99958C, hexDark: 0x7C7871)
    static let line     = Color(hexLight: 0xE8E5DE, hexDark: 0x3E3E3B)
    /// 陶土橙
    static let accent   = Color(hexLight: 0xD97757, hexDark: 0xD97757)
    static let accentBg = Color(hexLight: 0xF7EBE5, hexDark: 0x3D302B)

    static let green    = Color(hexLight: 0x4E8A62, hexDark: 0x6DAE83)
    static let amber    = Color(hexLight: 0xC08442, hexDark: 0xD9A05B)
    static let red      = Color(hexLight: 0xC0574B, hexDark: 0xD97C70)
    static let blue     = Color(hexLight: 0x5B7FA6, hexDark: 0x7FA3C8)

    static func gradeColor(_ g: Grade) -> Color {
        switch g {
        case .again: return red
        case .hard:  return amber
        case .good:  return green
        case .easy:  return blue
        }
    }

    // 字体
    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static let radius: CGFloat = 16
    static let pad: CGFloat = 18
}

// MARK: - 通用组件

/// 一整块内容卡：白底、大圆角、极淡描边，不用阴影
struct Panel<Content: View>: View {
    var padding: CGFloat = T.pad
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(T.surface)
            .clipShape(RoundedRectangle(cornerRadius: T.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: T.radius, style: .continuous)
                    .stroke(T.line, lineWidth: 1)
            )
    }
}

/// 分组小标题，全角间距的小字
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(T.sans(12.5, .medium))
            .foregroundColor(T.faint)
            .textCase(nil)
            .padding(.leading, 4)
            .padding(.bottom, 2)
    }
}

/// 主按钮：陶土橙实心胶囊
struct PrimaryButtonStyle: ButtonStyle {
    var enabled: Bool = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(T.sans(16, .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(enabled ? T.accent : T.faint)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

/// 次按钮：描边胶囊
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(T.sans(15.5, .medium))
            .foregroundColor(T.text)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(T.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(T.line, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// 一行可点的条目，右边一个浅箭头
struct RowButton<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var chevron: Bool = true
    @ViewBuilder var trailing: Trailing
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(T.sans(16)).foregroundColor(T.text)
                    if let subtitle {
                        Text(subtitle).font(T.sans(12.5)).foregroundColor(T.faint)
                    }
                }
                Spacer(minLength: 8)
                trailing
                if chevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(T.faint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension RowButton where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, chevron: Bool = true,
         action: @escaping () -> Void) {
        self.init(title: title, subtitle: subtitle, chevron: chevron,
                  trailing: { EmptyView() }, action: action)
    }
}

/// 细分割线，比系统的淡
struct Hair: View {
    var body: some View {
        Rectangle().fill(T.line).frame(height: 1)
    }
}

/// 小胶囊标签
struct Tag: View {
    let text: String
    var color: Color = T.dim
    var bg: Color = T.sunken
    var body: some View {
        Text(text)
            .font(T.sans(12, .medium))
            .foregroundColor(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 3.5)
            .background(bg)
            .clipShape(Capsule())
    }
}

/// 统一的页面壳：暖底 + 可滚动 + 大标题用衬线
struct Screen<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            T.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(T.serif(30, .semibold))
                            .foregroundColor(T.text)
                        if let subtitle {
                            Text(subtitle)
                                .font(T.sans(14))
                                .foregroundColor(T.dim)
                        }
                    }
                    .padding(.top, 6)

                    content
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
        }
    }
}
