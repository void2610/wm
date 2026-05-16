import AppKit

// bundle id 指定のアプリ起動・activate を担当する。Phase 3 で本実装する。
enum AppLauncher {
    // 指定 bundle id のアプリを起動、または既に起動済みなら最前面に呼ぶ
    static func launch(bundleId: String) {
        // Phase 3: NSWorkspace.shared.openApplication(at:configuration:) を使う
    }
}
