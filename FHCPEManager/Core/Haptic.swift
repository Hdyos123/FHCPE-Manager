import SwiftUI
import UIKit

/// 统一触感反馈
///
/// 用法：
///   Haptic.light()      轻点（按钮按下）
///   Haptic.medium()     中等（开关切换）
///   Haptic.success()    成功（操作完成）
///   Haptic.warning()    警告（失败/危险）
///   Haptic.selection()  选择变更
enum Haptic {
    /// 轻触反馈（可用性最强，适合绝大多数按钮）
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func heavy() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

/// 给按钮加触感的修饰器
struct HapticTap: ViewModifier {
    var style: Style = .light

    enum Style { case light, medium, success, warning, selection }

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            TapGesture().onEnded {
                switch style {
                case .light:    Haptic.light()
                case .medium:   Haptic.medium()
                case .success:  Haptic.success()
                case .warning:  Haptic.warning()
                case .selection: Haptic.selection()
                }
            }
        )
    }
}

extension View {
    /// 点击时触发触感
    func haptic(_ style: HapticTap.Style = .light) -> some View {
        modifier(HapticTap(style: style))
    }
}
