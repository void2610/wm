import SwiftUI

// プレビューウィンドウの中身。半透明角丸 + 枠線。
// 表示状態をバインディングで受け取り、SwiftUI 側で spring アニメーションを行う
struct PreviewView: View {
    let isVisible: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.35), lineWidth: 1.2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 2)
                    .blur(radius: 2)
            )
            .scaleEffect(isVisible ? 1.0 : 0.92)
            .opacity(isVisible ? 1.0 : 0)
            .animation(Anim.snapSpring, value: isVisible)
            .padding(2)
    }
}
