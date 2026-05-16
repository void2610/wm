import SwiftUI

// アクセシビリティ権限が無いときに表示する案内シート。Phase 1〜5 で順次仕上げる。
struct OnboardingView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("アクセシビリティ権限が必要です")
                .font(.title2)
                .bold()
            Text("システム設定 > プライバシーとセキュリティ > アクセシビリティ で MyWM を許可してください。")
                .multilineTextAlignment(.center)
            Button("システム設定を開く") {
                // Phase 1: x-apple.systempreferences の URL を NSWorkspace で開く
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(32)
        .frame(width: 420)
    }
}
