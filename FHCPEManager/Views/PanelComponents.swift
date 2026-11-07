import SwiftUI

// MARK: - 通用卡片容器
//
// 参考设计：深色半透明卡片，圆角 22，细描边，无重阴影
struct PanelCard<Content: View>: View {
    var padding: CGFloat = 16
    var radius: CGFloat = 22
    @ViewBuilder var content: () -> Content

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(scheme == .dark
                          ? Color.white.opacity(0.06)
                          : Color.white.opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [
                            Color.white.opacity(scheme == .dark ? 0.14 : 0.9),
                            Color.white.opacity(0.03)
                        ], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
            )
    }
}

// MARK: - 卡片标题行
struct PanelTitle: View {
    let text: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .center) {
            Text(text)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.primary)
            Spacer()
            if let t = trailing { t }
        }
    }
}

// MARK: - 横向信息胶囊（CPU / 内存 / 运行时长）
struct StatChip: View {
    let icon: String
    let label: String
    let value: String
    var tint: Color = .blue
    var progress: Double? = nil

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(Circle().fill(tint.opacity(0.15)))

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 0)

            if let p = progress {
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.18)).frame(width: 34, height: 4)
                    Capsule().fill(tint).frame(width: max(2, 34 * min(1, max(0, p))), height: 4)
                }
            }
        }
    }
}

// MARK: - 数值 + 单位（统一排版）
struct ValueUnit: View {
    let value: String
    let unit: String
    var color: Color = .primary
    var size: CGFloat = 22

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(value)
                .font(.system(size: size, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(unit)
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(color.opacity(0.6))
        }
    }
}

// MARK: - 指标条（RSRP / RSRQ 等，带彩色进度）
struct MetricBar: View {
    let label: String
    let value: String
    let unit: String
    let progress: Double     // 0...1
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value.isEmpty ? "--" : value)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
                Text(unit)
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.16)).frame(height: 4)
                GeometryReader { g in
                    Capsule()
                        .fill(color)
                        .frame(width: max(3, g.size.width * min(1, max(0, progress))), height: 4)
                }
                .frame(height: 4)
            }
            .padding(.horizontal, 6)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 设置行（图标 + 标题 + 副标题 + 右侧）
struct SettingRow<Trailing: View>: View {
    let icon: String
    let iconTint: Color
    let title: String
    var subtitle: String? = nil
    var subtitleTint: Color? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(iconTint)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(iconTint.opacity(0.14))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(.primary)
                if let s = subtitle {
                    Text(s)
                        .font(.system(size: 11))
                        .foregroundStyle(subtitleTint ?? .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            trailing()
        }
        .padding(.vertical, 6)
    }
}


// MARK: - 全局深色背景（参考设计：深蓝黑渐变 + 微光晕）
struct AppBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            if scheme == .dark {
                LinearGradient(
                    colors: [
                        Color(red: 0.043, green: 0.055, blue: 0.09),
                        Color(red: 0.067, green: 0.086, blue: 0.14),
                        Color(red: 0.051, green: 0.067, blue: 0.098)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            } else {
                LinearGradient(
                    colors: [Color(red: 0.95, green: 0.96, blue: 0.99),
                             Color(red: 0.92, green: 0.94, blue: 0.98)],
                    startPoint: .top, endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
    }
}
