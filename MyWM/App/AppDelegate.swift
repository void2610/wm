import AppKit

// NSApplicationDelegate。アプリ起動時のオーケストレーションを行う。
// - Dock を出さず accessory にする
// - アクセシビリティ権限のチェックと polling
// - 権限取得後に ConfigManager と HotkeyManager を起動
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let permissionMonitor = PermissionMonitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // 権限取得後の初期化を一度だけ走らせる
        permissionMonitor.onTrusted = { [weak self] in
            self?.bootstrapAfterPermission()
        }

        if AccessibilityClient.isTrusted() {
            // 既に許可済みなら即座に初期化
            bootstrapAfterPermission()
        } else {
            // 未許可なら Onboarding を出し、初回プロンプトを促す
            AppWindows.showOnboarding(monitor: permissionMonitor)
            PermissionMonitor.requestPrompt()
            permissionMonitor.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregisterAll()
        permissionMonitor.stop()
    }

    // 権限取得後に呼ばれる初期化
    private func bootstrapAfterPermission() {
        ConfigManager.shared.bootstrap()
        HotkeyManager.shared.attachToConfig()
        AppWindows.closeOnboarding()
        Log.app.info("初期化完了")
    }
}
