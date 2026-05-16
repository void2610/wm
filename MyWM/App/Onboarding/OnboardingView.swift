import SwiftUI

// アクセシビリティ権限が無いときに表示する案内ウィンドウ。
// 「システム設定を開く」と「再チェック」のボタンを提供する。
struct OnboardingView: View {
    @ObservedObject var monitor: PermissionMonitor

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("アクセシビリティ権限が必要です")
                .font(.title2)
                .bold()

            Text("MyWM はキーボードからウィンドウを移動・リサイズするためにアクセシビリティ権限を必要とします。\n下のボタンからシステム設定を開いて MyWM にチェックを入れてください。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button("システム設定を開く") {
                    PermissionMonitor.requestPrompt()
                    PermissionMonitor.openSystemSettings()
                }
                .keyboardShortcut(.defaultAction)
            }

            if monitor.isTrusted {
                Label("権限が確認できました", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(32)
        .frame(width: 440)
    }
}
