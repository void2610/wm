import SwiftUI

// プレビューウィンドウの中身。
// in/out のフェードは PreviewWindow 側で panel.alphaValue を NSAnimationContext で
// 補間する設計なので、ここでは opacity を扱わない。中身の rect 位置補間のみ担当する
struct PreviewView: View {
    @ObservedObject var viewModel: PreviewViewModel

    var body: some View {
        let r = viewModel.rect
        let overlay = viewModel.overlayFrame
        let localX = r.minX - overlay.minX
        let localTop = overlay.maxY - r.maxY

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
        }
        // generation を id にすることで、show() ごとに view ツリーが再生成され、
        // SwiftUI の補間器・@State が完全にリセットされる
        .id(viewModel.generation)
    }
}
