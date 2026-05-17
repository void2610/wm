import AppKit

// NSApplicationDelegate。アプリ起動時のオーケストレーションを行う。
// - 通常時は accessory（Dock 無し）で常駐
// - 権限未許可時のみ .regular に切替えて Onboarding を前面化
// - 権限取得後に ConfigManager と HotkeyManager を起動
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let permissionMonitor = PermissionMonitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 権限取得後の初期化を一度だけ走らせる
        permissionMonitor.onTrusted = { [weak self] in
            MainActor.assumeIsolated {
                self?.bootstrapAfterPermission()
            }
        }

        if AccessibilityClient.isTrusted() {
            // 既に許可済みなら accessory のまま起動
            NSApp.setActivationPolicy(.accessory)
            bootstrapAfterPermission()
        } else {
            // 未許可なら .regular に切替えて Onboarding を前面化
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
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
        NSApp.setActivationPolicy(.accessory)
        ConfigManager.shared.bootstrap()
        HotkeyManager.shared.attachToConfig()
        AppWindows.closeOnboarding()
        Log.app.info("初期化完了")
    }
}
