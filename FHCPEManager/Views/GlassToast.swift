import SwiftUI

/// 顶部消息类型
enum ToastKind {
    case success, info, error

    var color: Color {
        switch self {
        case .success: return Color(red: 0.2, green: 0.78, blue: 0.45)
        case .info:    return Color(red: 0.35, green: 0.55, blue: 0.98)
        case .error:   return Color(red: 0.92, green: 0.35, blue: 0.32)
        }
    }

    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .info:    return "info.circle.fill"
        case .error:   return "exclamationmark.triangle.fill"
        }
    }
}

/// 顶部玻璃通知横幅（从顶部滑入）
struct GlassToast: View {
    let text: String
    let kind: ToastKind

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: kind.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(kind.color)

            Text(text)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(Color(white: 0.18))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.55))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [
                        Color.white.opacity(0.95),
                        kind.color.opacity(0.25)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1.1
                )
        )
        .shadow(color: kind.color.opacity(0.18), radius: 14, x: 0, y: 6)
        .padding(.horizontal, 16)
    }
}
