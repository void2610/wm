import AppKit

// bundle id 指定の .app 起動と、path 指定の任意実行ファイル起動を担当する。
// .app は activate / openApplication 経由、それ以外の実行ファイルは Process で起動する
enum AppLauncher {

    // 指定 bundle id のアプリを起動、または既に起動済みなら最前面に呼ぶ。
    // 既に対象アプリが frontmost のときは、同アプリ内の別ウィンドウへ巡回する
    static func launch(bundleId: String) {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        if let app = running.first {
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleId,
               cycleToNextWindow(pid: app.processIdentifier) {
                Log.app.info("同アプリ別ウィンドウへ巡回: \(bundleId)")
                return
            }
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

    // 指定 path の実行ファイルまたは .app バンドルを起動する。
    // .app バンドルは LaunchServices 経由で適切に activate 状態にできるが、
    // 単独 Mach-O 実行ファイルは LaunchServices に登録されないので Process で起動する
    static func launch(path: String) {
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)

        // .app バンドルなら openApplication 経由
        if url.pathExtension == "app" {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
                if let error {
                    Log.app.error("アプリ起動に失敗: \(expanded) \(String(describing: error))")
                } else {
                    Log.app.info("アプリ起動: \(expanded)")
                }
            }
            return
        }

        // 起動済みの同実行ファイルがあれば activate する。
        // bundle id を持たないので executableURL の実体パスでマッチング判定する
        let resolvedTarget = url.resolvingSymlinksInPath().path
        if let running = NSWorkspace.shared.runningApplications.first(where: { app in
            guard let exe = app.executableURL?.resolvingSymlinksInPath().path else { return false }
            return exe == resolvedTarget
        }) {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == running.processIdentifier,
               cycleToNextWindow(pid: running.processIdentifier) {
                Log.app.info("同アプリ別ウィンドウへ巡回: \(expanded)")
                return
            }
            running.activate(options: [.activateIgnoringOtherApps])
            Log.app.info("起動済み実行ファイルを activate: \(expanded)")
            return
        }

        // 未起動なら Process で起動
        let process = Process()
        process.executableURL = url
        do {
            try process.run()
            Log.app.info("実行ファイル起動: \(expanded)")
        } catch {
            Log.app.error("実行ファイル起動に失敗: \(expanded) \(String(describing: error))")
        }
    }

    // 指定 pid のアプリの focused window 以外のウィンドウへ巡回し raise する。
    // ウィンドウが 1 つしか無い、または focused が無いなどで巡回不能なら false
    private static func cycleToNextWindow(pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        let windows = AccessibilityClient.windows(of: app)
        guard windows.count >= 2 else { return false }

        // focused window のインデックスを起点に、次のウィンドウを raise する。
        // focused が特定できなければ先頭から
        let focused = AccessibilityClient.focusedWindow(of: app)
        let baseIndex: Int
        if let focused, let idx = windows.firstIndex(where: { CFEqual($0, focused) }) {
            baseIndex = idx
        } else {
            baseIndex = -1
        }
        let nextIndex = (baseIndex + 1) % windows.count
        return AccessibilityClient.raise(windows[nextIndex])
    }
}
