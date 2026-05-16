import SwiftUI

// プレビューウィンドウの中身。半透明角丸 + 枠線。
// Phase 4 で本実装する。
struct PreviewView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.3), lineWidth: 1)
            )
    }
}
