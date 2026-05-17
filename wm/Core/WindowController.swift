import AppKit
import ApplicationServices

// 高レベルのウィンドウ操作 API。
// snap (1/2, 1/4)、maximize、center、toggleFullscreen を提供する。
// 内部で AccessibilityClient を使って実ウィンドウへ反映する。
// AX / NSWorkspace / PreviewWindow を触るため main actor に固定する
@MainActor
enum WindowController {

    // MARK: - スナップ系のエントリポイント

    static func snapToLeftHalf() {
        snap { screen, padding in screen.leftHalf(padding: padding) }
    }

    static func snapToRightHalf() {
        snap { screen, padding in screen.rightHalf(padding: padding) }
    }

    static func snapToTopHalf() {
        snap { screen, padding in screen.topHalf(padding: padding) }
    }

    static func snapToBottomHalf() {
        snap { screen, padding in screen.bottomHalf(padding: padding) }
    }

    static func snapToTopLeftQuarter() {
        snap { screen, padding in screen.topLeftQuarter(padding: padding) }
    }

    static func snapToTopRightQuarter() {
        snap { screen, padding in screen.topRightQuarter(padding: padding) }
    }

    static func snapToBottomLeftQuarter() {
        snap { screen, padding in screen.bottomLeftQuarter(padding: padding) }
    }

    static func snapToBottomRightQuarter() {
        snap { screen, padding in screen.bottomRightQuarter(padding: padding) }
    }

    static func maximize() {
        snap { screen, padding in screen.paddedVisibleFrame(padding: padding) }
    }

    // 現在のサイズを保ったまま画面中央に配置する
    static func center() {
        guard let target = focusedTarget() else { return }
        let screen = currentScreen(of: target.window)
        guard let currentFrame = AccessibilityClient.getFrame(target.window) else { return }
        // currentFrame は AX 座標なのでサイズだけ流用し、中心は visibleFrame から計算
        let visibleAX = NSScreen.convertToAX(screen.visibleFrame)
        let cx = visibleAX.midX
        let cy = visibleAX.midY
        let centered = CGRect(
            x: cx - currentFrame.width / 2,
            y: cy - currentFrame.height / 2,
            width: currentFrame.width,
            height: currentFrame.height
        )
        applyFrame(centered, to: target)
    }

    // ネイティブのフルスクリーンをトグルする
    static func toggleFullscreen() {
        guard let target = focusedTarget() else { return }
        AccessibilityClient.toggleFullscreen(target.window)
    }

    // MARK: - 内部

    // 現在のフォーカスターゲット（app + window + bundleId）を返す
    private struct Target {
        let app: AXUIElement
        let window: AXUIElement
        let bundleId: String?
    }

    private static func focusedTarget() -> Target? {
        guard let frontApp = AccessibilityClient.frontmostApp() else { return nil }
        guard let window = AccessibilityClient.focusedWindow(of: frontApp.element) else { return nil }
        let bundleId = NSRunningApplication(processIdentifier: frontApp.pid)?.bundleIdentifier
        return Target(app: frontApp.element, window: window, bundleId: bundleId)
    }

    // ウィンドウ中心の AX 座標から、属するスクリーンを判定する
    private static func currentScreen(of window: AXUIElement) -> NSScreen {
        guard let frame = AccessibilityClient.getFrame(window) else {
            return NSScreen.main ?? NSScreen.screens[0]
        }
        let centerAX = CGPoint(x: frame.midX, y: frame.midY)
        return NSScreen.containingAX(point: centerAX)
    }

    // snap 系の共通処理。compute は NSScreen 座標で目標枠を返すクロージャ
    private static func snap(_ compute: (NSScreen, CGFloat) -> CGRect) {
        guard let target = focusedTarget() else { return }
        let screen = currentScreen(of: target.window)
        let padding = CGFloat(ConfigManager.shared.current.general.padding)
        let nsRect = compute(screen, padding)

        // 1 回目（パネル非表示）でも現ウィンドウからスライドさせるため
        // 現在の AX frame を NSScreen 座標に直して from として渡す
        let fromNS: CGRect? = AccessibilityClient.getFrame(target.window)
            .map { NSScreen.convertFromAX($0) }

        // プレビューを表示してから実ウィンドウを更新する（Phase 4）。
        // autoHideAfter はスライドアニメ duration と一致させ、スライド完走と同時に
        // フェード退出が始まるようにする。これでスライド中にフェードが先取りされる
        // 「フェード中スライド」現象を消す
        let animDur = ConfigManager.shared.current.general.animationDuration
        PreviewWindow.shared.show(at: nsRect, from: fromNS, autoHideAfter: animDur)

        let axRect = NSScreen.convertToAX(nsRect)
        applyFrame(axRect, to: target)
    }

    // AXEnhancedUserInterface を活用しつつ frame を適用する
    private static func applyFrame(_ axFrame: CGRect, to target: Target) {
        let excluded = Set(ConfigManager.shared.current.general.enhancedUIExcluded)
        AccessibilityClient.setFrameSmoothing(
            window: target.window,
            app: target.app,
            frame: axFrame,
            skipEnhancedFor: target.bundleId,
            excluded: excluded
        )
    }
}
