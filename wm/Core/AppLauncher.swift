import AppKit

// bundle id 指定の .app 起動と、path 指定の任意実行ファイル起動を担当する。
// .app は activate / openApplication 経由、それ以外の実行ファイルは Process で起動する
enum AppLauncher {

    // 指定 bundle id のアプリを起動、または既に起動済みなら最前面に呼ぶ。
    // 既に対象アプリが frontmost のときは、同アプリ内の別ウィンドウへ巡回する
    static func launch(bundleId: String) {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        if !running.isEmpty {
            // どれかのインスタンスが active なら巡回モード。
            // 同一プロセス内の別ウィンドウ → 別 Space の同アプリウィンドウ の順で試す。
            // 別 Space 巡回が false（target がフルスクリーン Space などで未対応）の場合は
            // 通常 activate にフォールバックし、macOS のシステム挙動に任せる
            if let activeApp = running.first(where: { $0.isActive }) {
                let pid = activeApp.processIdentifier
                if cycleToNextWindow(pid: pid) {
                    Log.app.info("同アプリ別ウィンドウへ巡回: \(bundleId)")
                    return
                }
                let app = AXUIElementCreateApplication(pid)
                let focused = AccessibilityClient.focusedWindow(of: app)
                if SpaceManager.cycleToAnotherSpaceWindow(pid: pid, focusedWindow: focused) {
                    Log.app.info("別 Space の同アプリウィンドウへ巡回: \(bundleId)")
                    return
                }
            }
            running[0].activate(options: [.activateIgnoringOtherApps])
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
        let matching = NSWorkspace.shared.runningApplications.filter { app in
            guard let exe = app.executableURL?.resolvingSymlinksInPath().path else { return false }
            return exe == resolvedTarget
        }
        if !matching.isEmpty {
            if let activeApp = matching.first(where: { $0.isActive }) {
                if cycleToNextWindow(pid: activeApp.processIdentifier) {
                    Log.app.info("同アプリ別ウィンドウへ巡回: \(expanded)")
                    return
                }
            }
            matching[0].activate(options: [.activateIgnoringOtherApps])
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
    // ウィンドウが 1 つしか無いなど巡回不能なら false。
    // AXUIElement は同一ウィンドウでも別インスタンスが返ることがあり CFEqual での
    // 同一性比較が信頼できないため、frame で focused window を識別する
    private static func cycleToNextWindow(pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        let windows = AccessibilityClient.windows(of: app)
        Log.app.info("cycle: windows.count=\(windows.count)")
        guard windows.count >= 2 else { return false }

        let focusedFrame = AccessibilityClient.focusedWindow(of: app)
            .flatMap { AccessibilityClient.getFrame($0) }
        Log.app.info("cycle: focusedFrame=\(String(describing: focusedFrame))")

        // focused と frame が一致するもののインデックスを起点に、次のウィンドウを raise する。
        // 一致が無ければ先頭から
        var baseIndex = -1
        if let focusedFrame {
            for (i, w) in windows.enumerated() {
                if let f = AccessibilityClient.getFrame(w), f == focusedFrame {
                    baseIndex = i
                    break
                }
            }
        }
        let nextIndex = (baseIndex + 1) % windows.count
        Log.app.info("cycle: baseIndex=\(baseIndex) nextIndex=\(nextIndex)")
        let next = windows[nextIndex]
        // kAXRaiseAction だけでは z-order が上がるだけで focused window 扱いに
        // ならないアプリがあるため、main / focused 属性を明示的に true にする
        AXUIElementSetAttributeValue(next, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(next, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        let raised = AccessibilityClient.raise(next)
        Log.app.info("cycle: raised=\(raised)")
        return raised
    }
}
