import AppKit

// NSApplicationDelegate。起動時のアクセシビリティ権限チェック等を担当する
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock アイコンを出さず、Activation Policy を accessory に固定する
        NSApp.setActivationPolicy(.accessory)

        // Phase 1: AccessibilityClient の権限チェックを呼ぶ
        // Phase 2: ConfigManager をロードする
        // Phase 1: HotkeyManager をセットアップする
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Phase 1: HotkeyManager をクリーンアップする
    }
}
