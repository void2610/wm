import AppKit
import Combine

// アクセシビリティ権限の許可状態を 1Hz で polling する。
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
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let trusted = AccessibilityClient.isTrusted()
                if trusted != self.isTrusted {
                    self.isTrusted = trusted
                }
                if trusted {
                    self.timer?.invalidate()
                    self.timer = nil
                    self.onTrusted?()
                }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
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
}
