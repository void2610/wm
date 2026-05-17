import SwiftUI

// アクセシビリティ権限が無いときに表示する案内ウィンドウ。
// 「システム設定を開く」「再チェック」「再起動」のボタンを提供する。
struct OnboardingView: View {
    @ObservedObject var monitor: PermissionMonitor

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: monitor.isTrusted ? "checkmark.seal.fill" : "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(monitor.isTrusted ? Color.green : Color.secondary)

            Text(monitor.isTrusted ? "権限が確認できました" : "アクセシビリティ権限が必要です")
                .font(.title2)
                .bold()

            Text("MyWM はキーボードからウィンドウを移動・リサイズするためにアクセシビリティ権限を必要とします。\nシステム設定で MyWM にチェックを入れると自動的に進みます。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button("システム設定を開く") {
                    PermissionMonitor.requestPrompt()
                    PermissionMonitor.openSystemSettings()
                }
                .keyboardShortcut(.defaultAction)

                Button("再チェック") {
                    monitor.recheck()
                }
            }
        }
        .padding(32)
        .frame(width: 460)
    }
}
