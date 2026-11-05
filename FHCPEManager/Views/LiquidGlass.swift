import SwiftUI

// MARK: - 液态玻璃（真折射版）
//
// 用 Metal shader 采样背景并做边缘弯折，IOS 17+ 的 SwiftUI 支持
// `.layerEffect` / `.distortionEffect`，低版本自动退回材质模糊。

struct LiquidGlassRefractionModifier: ViewModifier {
    var radius: CGFloat = 24
    var strong: Bool = false
    var tint: Color? = nil

    @Environment(\.colorScheme) private var scheme

    private var tintRGB: (Double, Double, Double) {
        guard let tint else {
            return scheme == .dark ? (0.62, 0.70, 0.90) : (1.0, 1.0, 1.0)
        }
        let ui = UIColor(tint)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
    }

    func body(content: Content) -> some View {
        // 关键：只裁背景，不裁 content
        // 否则 overlay 在卡片边角外的元素（刷新胶囊、编辑笔）会被切掉
        if #available(iOS 26.0, *) {
            content
                .background {
                    GlassBackdrop(radius: radius, strong: strong, tintRGB: tintRGB)
                }
        } else {
            content
                .background {
                    ZStack {
                        GlassBackdrop(radius: radius, strong: strong, tintRGB: tintRGB)
                            .clipShape(RoundedRectangle(cornerRadius: radius,
                                                        style: .continuous))

                        LiquidRim(radius: radius,
                                  lineWidth: 1.0,
                                  intensity: scheme == .dark ? 0.55 : 0.95)
                            .clipShape(RoundedRectangle(cornerRadius: radius,
                                                        style: .continuous))
                            .allowsHitTesting(false)
                    }
                }
                .shadow(color: Color.black.opacity(0.10),
                        radius: 14, x: 0, y: 5)
        }
    }
}

/// 背景层：iOS 17+ 走折射，低版本退回毛玻璃
private struct GlassBackdrop: View {
    let radius: CGFloat
    let strong: Bool
    let tintRGB: (Double, Double, Double)
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                if #available(iOS 17.0, *) {
                    // 真折射：shader 按边缘法线弯折采样（iOS 17 API，Xcode 15 可编译）
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .layerEffect(
                            ShaderLibrary.liquidGlassRefraction(
                                .float2(Float(size.width), Float(size.height)),
                                .float(radius),
                                .float(26),
                                .float(strong ? 16 : 11),
                                .float3(Float(tintRGB.0), Float(tintRGB.1), Float(tintRGB.2)),
                                .float(scheme == .dark ? 0.16 : 0.06),
                                .float(.pi * 1.25)
                            ),
                            maxSampleOffset: CGSize(width: 24, height: 24)
                        )
                } else {
                    Rectangle().fill(.ultraThinMaterial)
                }

                // 实体感
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(scheme == .dark
                          ? Color.white.opacity(strong ? 0.055 : 0.032)
                          : Color.white.opacity(strong ? 0.50 : 0.38))

                // 对角高光
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LinearGradient(
                        colors: [
                            Color.white.opacity(scheme == .dark ? 0.09 : 0.50),
                            .clear
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }
}

/// 边缘描边层
private struct LiquidRim: View {
    let radius: CGFloat
    let lineWidth: CGFloat
    let intensity: Double

    var body: some View {
        // 用渐变描边即可：colorEffect 的输入是整块矩形，
        // 会在卡片上留下斜向亮带，故不用 shader 画边。
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(intensity),
                        Color.white.opacity(intensity * 0.18),
                        Color.black.opacity(0.08)
                    ],
                    startPoint: .top, endPoint: .bottom
                ),
                lineWidth: lineWidth
            )
    }
}

extension View {
    /// 液态玻璃卡片（真折射）
    func liquidGlass(radius: CGFloat = 24, strong: Bool = false, tint: Color? = nil) -> some View {
        modifier(LiquidGlassRefractionModifier(radius: radius, strong: strong, tint: tint))
    }
}

// MARK: - 液态玻璃胶囊 Tab 栏
//
// 底部悬浮胶囊 + 选中项玻璃药丸滑动

struct LiquidTabBar: View {
    struct Item: Identifiable {
        let id: Int
        let title: String
        let icon: String
    }

    let items: [Item]
    @Binding var selection: Int
    @Namespace private var ns

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                tabButton(item)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background {
            // 整条胶囊底座：液态玻璃
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .fill(scheme == .dark
                              ? Color.white.opacity(0.06)
                              : Color.white.opacity(0.48))
                }
                .overlay {
                    // 顶部高光带
                    Capsule(style: .continuous)
                        .fill(LinearGradient(
                            colors: [
                                Color.white.opacity(scheme == .dark ? 0.18 : 0.75),
                                .clear, .clear
                            ],
                            startPoint: .top, endPoint: .bottom))
                        .blendMode(.plusLighter)
                        .opacity(0.6)
                }
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(scheme == .dark ? 0.38 : 1.0),
                                    Color.white.opacity(scheme == .dark ? 0.05 : 0.30),
                                    Color.black.opacity(scheme == .dark ? 0.22 : 0.05)
                                ],
                                startPoint: .top, endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                }
        }
        .shadow(color: Color.black.opacity(scheme == .dark ? 0.55 : 0.12),
                radius: 24, x: 0, y: 10)
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
    }

    private func tabButton(_ item: Item) -> some View {
        let on = selection == item.id
        return Button {
            guard !on else { return }
            Haptic.light()
            withAnimation(.spring(response: 0.36, dampingFraction: 0.74)) {
                selection = item.id
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: item.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(height: 20)
                    .symbolRenderingMode(.hierarchical)
                Text(item.title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(on ? Color.accentColor : Color.secondary.opacity(0.85))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background {
                if on {
                    // 选中项：跟随滑动的玻璃药丸
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Capsule(style: .continuous)
                                .fill(Color.accentColor.opacity(scheme == .dark ? 0.22 : 0.15))
                        }
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(scheme == .dark ? 0.42 : 0.98),
                                            Color.white.opacity(0.04)
                                        ],
                                        startPoint: .top, endPoint: .bottom
                                    ),
                                    lineWidth: 1
                                )
                        }
                        .shadow(color: Color.accentColor.opacity(scheme == .dark ? 0.35 : 0.22),
                                radius: 10, x: 0, y: 3)
                        .matchedGeometryEffect(id: "tabPill", in: ns)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
