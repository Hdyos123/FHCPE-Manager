import SwiftUI

/// 玻璃风列表背景：渐变底 + 半透明白卡片
struct GlassListBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            // 底色渐变
            LinearGradient(
                colors: scheme == .dark
                    ? [Color(red: 0.07, green: 0.09, blue: 0.15),
                       Color(red: 0.10, green: 0.13, blue: 0.20),
                       Color(red: 0.08, green: 0.10, blue: 0.17)]
                    : [Color(red: 0.93, green: 0.95, blue: 1.0),
                       Color(red: 0.96, green: 0.97, blue: 1.0),
                       Color(red: 0.94, green: 0.96, blue: 1.0)],
                startPoint: .top,
                endPoint: .bottom
            )

            // 光斑：让液态玻璃有东西可折射
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                ZStack {
                    Circle()
                        .fill(Color(red: 0.35, green: 0.55, blue: 0.98))
                        .frame(width: w * 0.85)
                        .blur(radius: 90)
                        .opacity(scheme == .dark ? 0.32 : 0.30)
                        .offset(x: -w * 0.30, y: -h * 0.32)

                    Circle()
                        .fill(Color(red: 0.62, green: 0.42, blue: 0.96))
                        .frame(width: w * 0.75)
                        .blur(radius: 100)
                        .opacity(scheme == .dark ? 0.28 : 0.24)
                        .offset(x: w * 0.34, y: -h * 0.10)

                    Circle()
                        .fill(Color(red: 0.20, green: 0.80, blue: 0.72))
                        .frame(width: w * 0.80)
                        .blur(radius: 110)
                        .opacity(scheme == .dark ? 0.24 : 0.20)
                        .offset(x: -w * 0.20, y: h * 0.34)
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// 统一玻璃卡片修饰（与首页一致）
struct GlassRowModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .listRowBackground(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(scheme == .dark
                                  ? Color.white.opacity(0.045)
                                  : Color.white.opacity(0.42))
                    )
                    .overlay(
                        // 顶部高光描边
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(scheme == .dark ? 0.30 : 0.92),
                                        Color.white.opacity(scheme == .dark ? 0.05 : 0.28),
                                        Color.black.opacity(scheme == .dark ? 0.18 : 0.04)
                                    ],
                                    startPoint: .top, endPoint: .bottom
                                ),
                                lineWidth: 0.8
                            )
                    )
                    .padding(.vertical, 2)
                    .padding(.horizontal, 4)
            )
            .listRowSeparator(.hidden)
    }
}

extension View {
    /// 应用到 List 上：玻璃背景
    func glassListStyle() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(GlassListBackground())
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 78)
            }

    }

    /// 应用到 List Row 上：玻璃卡片
    func glassRow() -> some View {
        modifier(GlassRowModifier())
    }
}


// MARK: - 液态玻璃卡片

/// 统一的液态玻璃卡片样式（性能优先：单层阴影 + 描边）
struct GlassCard: ViewModifier {
    var radius: CGFloat = 24
    var strong: Bool = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground).opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(strong ? 0.9 : 0.65),
                                Color.white.opacity(0.18),
                                Color.white.opacity(strong ? 0.5 : 0.32)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: strong ? 1.2 : 0.9
                    )
            )
    }
}

extension View {
    func glassCard(radius: CGFloat = 24, strong: Bool = false) -> some View {
        liquidGlass(radius: radius, strong: strong)
    }
}


// MARK: - 速率分档配色

/// 实测阈值：≥125 爆速 / ≥100 极速 / ≥20 正常 / ≥5 偏慢 / 其余异常
enum SpeedTier {
    case ultra, fast, good, slow, bad

    /// 阈值按 5G 实测校准
    /// 130-150 常见峰速要能落到「满速」紫档
    static func of(_ mbps: Double) -> SpeedTier {
        if mbps >= 120 { return .ultra }    // 满速，紫
        if mbps >= 60  { return .fast }     // 高速，青绿
        if mbps >= 25  { return .good }     // 流畅，蓝
        if mbps >= 2   { return .slow }     // 偏慢，橙
        return .bad                         // 卡顿，红
    }

    var color: Color {
        switch self {
        case .ultra:  return Color(red: 0.55, green: 0.36, blue: 0.96)  // 紫
        case .fast:   return Color(red: 0.09, green: 0.72, blue: 0.65)  // 青绿
        case .good:   return Color(red: 0.24, green: 0.55, blue: 0.99)  // 蓝
        case .slow:   return Color(red: 0.94, green: 0.63, blue: 0.29)  // 橙
        case .bad:    return Color(red: 0.90, green: 0.34, blue: 0.30)  // 红
        }
    }

    var label: String {
        switch self {
        case .ultra:  return "满速"
        case .fast:   return "高速"
        case .good:   return "流畅"
        case .slow:   return "偏慢"
        case .bad:    return "卡顿"
        }
    }

    var emoji: String {
        switch self {
        case .ultra:  return "🚀"
        case .fast:   return "⚡"
        case .good:   return "✅"
        case .slow:   return "🐢"
        case .bad:    return "🐌"
        }
    }
}
