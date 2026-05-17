import AppKit

// NSApplicationDelegate。アプリ起動時のオーケストレーションを行う。
// - LSUIElement=YES なので常に accessory として起動する。
//   ActivationPolicy を後から切り替えると SwiftUI の MenuBarExtra が
//   インストールされなくなるため、policy はいじらない方針。
// - Menu bar item は NSStatusItem を直接生成して保持する
// - 権限未許可時は Onboarding ウィンドウを NSApp.activate で前面化する
// - 権限取得後に ConfigManager と HotkeyManager を起動
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let permissionMonitor = PermissionMonitor()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock アイコンを出さず menu bar 常駐にする。LSUIElement は使わずここで設定する
        NSApp.setActivationPolicy(.accessory)

        // 起動と同時に menu bar item を出す。権限が無くてもアイコンは表示する
        setupStatusItem()

        permissionMonitor.onTrusted = { [weak self] in
            MainActor.assumeIsolated {
                self?.bootstrapAfterPermission()
            }
        }

        if AccessibilityClient.isTrusted() {
            bootstrapAfterPermission()
        } else {
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

    // MARK: - Menu bar item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            // SF Symbol。テンプレートとして扱わせるとダーク／ライトで自動反転される
            let image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "MyWM")
            image?.isTemplate = true
            button.image = image
            // 万一 image が nil でも見えるように title をフォールバックで設定
            if image == nil {
                button.title = "MyWM"
            }
            button.toolTip = "MyWM"
        }
        item.menu = buildMenu()
        statusItem = item
        Log.app.info("Menu bar item を生成しました")
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let openSettings = NSMenuItem(
            title: "設定…",
            action: #selector(openSettingsAction),
            keyEquivalent: ","
        )
        openSettings.target = self
        menu.addItem(openSettings)

        menu.addItem(.separator())

        let openConfig = NSMenuItem(
            title: "config ファイルを開く",
            action: #selector(openConfigAction),
            keyEquivalent: ""
        )
        openConfig.target = self
        menu.addItem(openConfig)

        let reloadConfig = NSMenuItem(
            title: "config を再読み込み",
            action: #selector(reloadConfigAction),
            keyEquivalent: ""
        )
        reloadConfig.target = self
        menu.addItem(reloadConfig)

        menu.addItem(.separator())

        let openA11ySettings = NSMenuItem(
            title: "アクセシビリティ設定を開く",
            action: #selector(openA11ySettingsAction),
            keyEquivalent: ""
        )
        openA11ySettings.target = self
        menu.addItem(openA11ySettings)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "MyWM を終了",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)

        return menu
    }

    @objc private func openSettingsAction() {
        AppWindows.showSettings()
    }

    @objc private func openConfigAction() {
        NSWorkspace.shared.open(ConfigManager.configPath)
    }

    @objc private func reloadConfigAction() {
        ConfigManager.shared.reload()
    }

    @objc private func openA11ySettingsAction() {
        PermissionMonitor.openSystemSettings()
    }
}
