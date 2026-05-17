import SwiftUI

// プレビューウィンドウの中身。
// 切り分け中: scale 系を全て外し、純粋な opacity のみで in/out させる
struct PreviewView: View {
    @ObservedObject var viewModel: PreviewViewModel
    let overlayFrameInScreen: CGRect

    var body: some View {
        let r = viewModel.rect
        let localX = r.minX - overlayFrameInScreen.minX
        let localTop = overlayFrameInScreen.maxY - r.maxY

        ZStack(alignment: .topLeading) {
            Color.clear

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
                .frame(width: r.width, height: r.height)
                .offset(x: localX, y: localTop)
                .opacity(viewModel.isVisible ? 1.0 : 0.0)
        }
    }
}
