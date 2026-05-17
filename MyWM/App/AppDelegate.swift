import AppKit

// NSApplicationDelegate。アプリ起動時のオーケストレーションを行う。
// - LSUIElement=YES なので常に accessory として起動する。
//   ActivationPolicy を後から切り替えると SwiftUI の MenuBarExtra が
//   インストールされなくなるため、policy はいじらない方針。
// - 権限未許可時は Onboarding ウィンドウを NSApp.activate で前面化する
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
            bootstrapAfterPermission()
        } else {
            // accessory のまま Onboarding を前面化する。activate でフォーカスを取りに行く。
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
        ConfigManager.shared.bootstrap()
        HotkeyManager.shared.attachToConfig()
        AppWindows.closeOnboarding()
        Log.app.info("初期化完了")
    }
}
