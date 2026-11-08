import SwiftUI

/// 大屏时限制内容宽度并居中，避免 iPad/横屏下内容过度拉伸
///
/// 注意：只按「实际可用宽度」判断，不能只看 sizeClass。
/// 早期版本只看 hSize/vSize，iPhone 横屏或分屏时会被误判成 wide，
/// 导致内容被压缩成一条窄柱。
struct WideAdapter<Content: View>: View {
    let maxWidth: CGFloat
    @ViewBuilder var content: () -> Content

    init(maxWidth: CGFloat = 560, @ViewBuilder content: @escaping () -> Content) {
        self.maxWidth = maxWidth
        self.content = content
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            if w > maxWidth + 40 {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    content()
                        .frame(width: maxWidth)
                    Spacer(minLength: 0)
                }
                .frame(width: w, height: geo.size.height)
            } else {
                content()
                    .frame(width: w, height: geo.size.height)
            }
        }
    }
}
