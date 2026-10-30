import SwiftUI

/// 玻璃风列表背景：渐变底 + 半透明白卡片
struct GlassListBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.93, green: 0.95, blue: 1.0),
                    Color(red: 0.96, green: 0.97, blue: 1.0),
                    Color(red: 0.94, green: 0.96, blue: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
}

/// 统一玻璃卡片修饰（与首页一致）
struct GlassRowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowBackground(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.62))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.85), lineWidth: 0.8)
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
        modifier(GlassCard(radius: radius, strong: strong))
    }
}


// MARK: - 速率分档配色

/// 实测阈值：≥125 爆速 / ≥100 极速 / ≥20 正常 / ≥5 偏慢 / 其余异常
enum SpeedTier {
    case ultra, fast, good, normal, slow, bad

    /// 阈值按 5G 实际体验划分（参考下行可用带宽）
    /// 之前 5Mbps 就算「疾驰」太离谱，已重新校准
    static func of(_ mbps: Double) -> SpeedTier {
        if mbps >= 300 { return .ultra }    // 满速 SAC/载波聚合
        if mbps >= 100 { return .fast }     // 高速
        if mbps >= 30  { return .good }     // 良好，可流畅看 4K
        if mbps >= 10  { return .normal }   // 一般
        if mbps >= 2   { return .slow }     // 偏慢，勉强刷视频
        return .bad                         // 卡顿
    }

    var color: Color {
        switch self {
        case .ultra:  return Color(red: 0.55, green: 0.36, blue: 0.96)  // 紫
        case .fast:   return Color(red: 0.09, green: 0.72, blue: 0.65)  // 青绿
        case .good:   return Color(red: 0.24, green: 0.55, blue: 0.99)  // 蓝
        case .normal: return Color(red: 0.55, green: 0.60, blue: 0.72)  // 灰蓝
        case .slow:   return Color(red: 0.94, green: 0.63, blue: 0.29)  // 橙
        case .bad:    return Color(red: 0.90, green: 0.34, blue: 0.30)  // 红
        }
    }

    var label: String {
        switch self {
        case .ultra:  return "满速"
        case .fast:   return "高速"
        case .good:   return "流畅"
        case .normal: return "一般"
        case .slow:   return "偏慢"
        case .bad:    return "卡顿"
        }
    }

    var emoji: String {
        switch self {
        case .ultra:  return "🚀"
        case .fast:   return "⚡"
        case .good:   return "✅"
        case .normal: return "➖"
        case .slow:   return "🐢"
        case .bad:    return "🐌"
        }
    }
}
