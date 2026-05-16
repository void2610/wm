import SwiftUI

// アプリのエントリポイント。LSUIElement = YES のメニューバー常駐アプリ。
@main
struct MyWMApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // メニューバーに常駐し、設定や Quit を提供する
        MenuBarExtra("MyWM", systemImage: "rectangle.split.2x1") {
            MenuBarContent()
        }
        .menuBarExtraStyle(.menu)
    }
}

// メニューバーから開けるメニュー本体
private struct MenuBarContent: View {
    var body: some View {
        Button("設定…") {
            AppWindows.showSettings()
        }
        .keyboardShortcut(",")

        Divider()

        Button("config ファイルを開く") {
            NSWorkspace.shared.open(ConfigManager.configPath)
        }
        Button("config を再読み込み") {
            ConfigManager.shared.reload()
        }

        Divider()

        Button("アクセシビリティ権限の状態") {
            // クリックでシステム設定を開く
            PermissionMonitor.openSystemSettings()
        }

        Divider()

        Button("MyWM を終了") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
