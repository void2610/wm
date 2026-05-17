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

            Text("MyWM はキーボードからウィンドウを移動・リサイズするためにアクセシビリティ権限を必要とします。\nシステム設定で MyWM にチェックを入れた後、自動で次に進まない場合は「再チェック」または「再起動」を押してください。")
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

                Button("MyWM を再起動") {
                    PermissionMonitor.relaunchSelf()
                }
            }

            DisclosureGroup("うまくいかない場合") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("• 未署名ビルドはビルドごとに code signature が変わるため、システム設定で MyWM の項目を一度削除（「-」ボタン）→ もう一度ドラッグして追加 → MyWM を再起動 してください。")
                    Text("• System Settings で MyWM のチェックを OFF → ON にしてから再起動するだけで通る場合もあります。")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .padding(.top, 4)
            }
            .padding(.horizontal, 8)
        }
        .padding(32)
        .frame(width: 480)
    }
}
