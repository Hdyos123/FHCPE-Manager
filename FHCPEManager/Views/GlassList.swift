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
