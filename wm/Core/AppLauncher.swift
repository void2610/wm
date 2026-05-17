import AppKit

// bundle id 指定のアプリ起動・activate を担当する。
// 既に起動済みなら activate して最前面に呼び、未起動なら openApplication で起動する。
enum AppLauncher {

    // 指定 bundle id のアプリを起動、または既に起動済みなら最前面に呼ぶ
    static func launch(bundleId: String) {
        // 起動済みインスタンスがあれば activate
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        if let app = running.first {
            app.activate(options: [.activateIgnoringOtherApps])
            Log.app.info("起動済みアプリを activate: \(bundleId)")
            return
        }

        // 未起動なら openApplication
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            Log.app.error("bundle id に対応するアプリが見つかりません: \(bundleId)")
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error {
                Log.app.error("アプリ起動に失敗: \(bundleId) \(String(describing: error))")
            } else {
                Log.app.info("アプリ起動: \(bundleId)")
            }
        }
    }
}
