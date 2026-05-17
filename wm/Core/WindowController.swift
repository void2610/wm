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

    // 上半分にある状態でもう一度上を入力すると全画面に巡回する
    static func snapToTopHalf() {
        snap(
            { screen, padding in screen.topHalf(padding: padding) },
            cycleTo: { screen, padding in screen.paddedVisibleFrame(padding: padding) }
        )
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

    // snap 系の共通処理。compute は NSScreen 座標で目標枠を返すクロージャ。
    // cycleTo が指定されていて、現ウィンドウが compute の結果と一致している場合は
    // 代わりに cycleTo の結果へ巡回する（例: 上半分の状態で再度上を入力 → 最大化）
    private static func snap(
        _ compute: (NSScreen, CGFloat) -> CGRect,
        cycleTo: ((NSScreen, CGFloat) -> CGRect)? = nil
    ) {
        guard let target = focusedTarget() else { return }
        let screen = currentScreen(of: target.window)
        let padding = CGFloat(ConfigManager.shared.current.general.padding)
        let primaryRect = compute(screen, padding)

        // 現ウィンドウの NSScreen 座標 frame。slide の起点としても、巡回判定にも使う
        let currentNS: CGRect? = AccessibilityClient.getFrame(target.window)
            .map { NSScreen.convertFromAX($0) }

        // 既に primary と一致していて cycleTo が指定されていれば、巡回先を採用する
        let nsRect: CGRect = {
            if let cycle = cycleTo,
               let cur = currentNS,
               Self.framesMatch(cur, primaryRect) {
                return cycle(screen, padding)
            }
            return primaryRect
        }()

        let fromNS: CGRect? = currentNS

        // プレビューを表示してから実ウィンドウを更新する（Phase 4）。
        // autoHideAfter はスライドアニメ duration と一致させ、スライド完走と同時に
        // フェード退出が始まるようにする。これでスライド中にフェードが先取りされる
        // 「フェード中スライド」現象を消す
        let animDur = ConfigManager.shared.current.general.animationDuration
        PreviewWindow.shared.show(at: nsRect, from: fromNS, autoHideAfter: animDur)

        let axRect = NSScreen.convertToAX(nsRect)
        applyFrame(axRect, to: target)
    }

    // 2 つの frame がほぼ一致しているか。AX 値の丸めやアプリ側のサイズ制約で
    // 数 px ずれることがあるため、広めの tolerance を持たせる
    private static func framesMatch(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 5.0) -> Bool {
        abs(a.minX - b.minX) < tolerance &&
        abs(a.minY - b.minY) < tolerance &&
        abs(a.width - b.width) < tolerance &&
        abs(a.height - b.height) < tolerance
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
