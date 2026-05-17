import AppKit
import Combine

// アクセシビリティ権限の許可状態を 1Hz で polling する。
// Timer は .common モードで run loop に追加するため、モーダル表示中も止まらない。
// 許可されたら onTrusted を呼び、polling を止める。
@MainActor
final class PermissionMonitor: ObservableObject {
    @Published var isTrusted: Bool = AccessibilityClient.isTrusted()

    private var timer: Timer?
    var onTrusted: (() -> Void)?

    func start() {
        if isTrusted {
            onTrusted?()
            return
        }
        timer?.invalidate()
        // .common モードで追加する。NSEventTrackingRunLoopMode 等のモーダル中でも止めない
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            // Timer のコールバックは main thread から呼ばれるが nonisolated 扱いなので明示的にラップ
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // 1Hz の polling 1 ステップ
    private func tick() {
        let trusted = AccessibilityClient.isTrusted()
        if trusted != isTrusted {
            isTrusted = trusted
        }
        if trusted {
            stop()
            onTrusted?()
        }
    }

    // 手動チェックを要求された場合に外部から呼べる
    func recheck() {
        tick()
    }

    // 「システム設定 > アクセシビリティ」を開く
    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // 初回プロンプトを出す
    static func requestPrompt() {
        _ = AccessibilityClient.isTrusted(prompt: true)
    }

    // 自分自身を再起動する。trust 状態の更新を確実に取り込む最終手段
    static func relaunchSelf() {
        let bundleURL = Bundle.main.bundleURL
        let process = Process()
        process.launchPath = "/usr/bin/open"
        process.arguments = ["-n", bundleURL.path]
        try? process.run()
        // 少し待ってから現プロセスを終了
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.terminate(nil)
        }
    }
}
