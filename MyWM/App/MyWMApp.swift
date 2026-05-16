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

// メニューバーから開けるメニュー本体。Phase 5 で本格実装する想定
private struct MenuBarContent: View {
    var body: some View {
        Button("設定…") {
            // Phase 5: 設定画面を開く
        }
        Divider()
        Button("config ファイルを開く") {
            // Phase 5: ~/.config/mywm/config.toml を開く
        }
        Button("config を reload") {
            // Phase 2: ConfigManager.reload() を呼ぶ
        }
        Divider()
        Button("MyWM を終了") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
