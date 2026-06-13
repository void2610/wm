import AppKit
import ApplicationServices

// 高レベルのウィンドウ操作 API。
// snap、maximize、center、toggleFullscreen を提供する。
// 内部で AccessibilityClient を使って実ウィンドウへ反映する。
// AX / NSWorkspace / PreviewWindow を触るため main actor に固定する
@MainActor
enum WindowController {

    // MARK: - スナップ系のエントリポイント

    // 左方向のスナップを 3 段階に巡回させる:
    //   左半分 → 左上 1/4 → 左下 1/4 → 左半分 → ...
    // それ以外の位置から押した場合は左半分。
    // 判定はサイズ制約のあるアプリでも効くよう「端揃え」ベースで行う
    static func snapToLeftHalf() {
        snap { screen, padding, currentNS in
            let leftHalf = screen.leftHalf(padding: padding)
            let topLeft = screen.topLeftQuarter(padding: padding)
            let bottomLeft = screen.bottomLeftQuarter(padding: padding)

            guard let cur = currentNS else { return leftHalf }
            if isAtLeftHalf(cur, screen: screen, padding: padding) { return topLeft }
            if isAtTopLeftQuarter(cur, screen: screen, padding: padding) { return bottomLeft }
            if isAtBottomLeftQuarter(cur, screen: screen, padding: padding) { return leftHalf }
            return leftHalf
        }
    }

    // 右方向のスナップを 3 段階に巡回させる:
    //   右半分 → 右上 1/4 → 右下 1/4 → 右半分 → ...
    static func snapToRightHalf() {
        snap { screen, padding, currentNS in
            let rightHalf = screen.rightHalf(padding: padding)
            let topRight = screen.topRightQuarter(padding: padding)
            let bottomRight = screen.bottomRightQuarter(padding: padding)

            guard let cur = currentNS else { return rightHalf }
            if isAtRightHalf(cur, screen: screen, padding: padding) { return topRight }
            if isAtTopRightQuarter(cur, screen: screen, padding: padding) { return bottomRight }
            if isAtBottomRightQuarter(cur, screen: screen, padding: padding) { return rightHalf }
            return rightHalf
        }
    }

    // 上半分にある状態でもう一度上を入力すると全画面に巡回する
    static func snapToTopHalf() {
        snap { screen, padding, currentNS in
            let topHalf = screen.topHalf(padding: padding)
            let maxRect = screen.paddedVisibleFrame(padding: padding)

            guard let cur = currentNS else { return topHalf }
            if isAtTopHalfPosition(cur, screen: screen, padding: padding) { return maxRect }
            return topHalf
        }
    }

    static func snapToBottomHalf() {
        snap { screen, padding, _ in screen.bottomHalf(padding: padding) }
    }

    static func maximize() {
        snap { screen, padding, _ in screen.paddedVisibleFrame(padding: padding) }
    }

    // 中央寄せ。
    //   中央未配置 → 現サイズのまま中央配置
    //   中央配置済み（中サイズではない） → 中サイズ（visible の 60% × 70%）で中央配置
    //   中サイズで中央配置済み → 変化なし
    // snap 共通処理を経由することでスライド+フェードのプレビューアニメも出る
    static func center() {
        snap { screen, _, currentNS in
            let visible = screen.visibleFrame
            let currentSize = currentNS?.size ?? .zero

            let mediumSize = CGSize(
                width: visible.width * 0.6,
                height: visible.height * 0.7
            )

            let centerTolerance: CGFloat = 4
            let isCentered: Bool = {
                guard let cur = currentNS else { return false }
                return abs(cur.midX - visible.midX) < centerTolerance
                    && abs(cur.midY - visible.midY) < centerTolerance
            }()
            let sizeTolerance: CGFloat = 4
            let isAlreadyMedium = abs(currentSize.width - mediumSize.width) < sizeTolerance
                              && abs(currentSize.height - mediumSize.height) < sizeTolerance

            let targetSize: CGSize = (isCentered && !isAlreadyMedium) ? mediumSize : currentSize

            return CGRect(
                x: visible.midX - targetSize.width / 2,
                y: visible.midY - targetSize.height / 2,
                width: targetSize.width,
                height: targetSize.height
            )
        }
    }

    // ネイティブのフルスクリーンをトグルする
    static func toggleFullscreen() {
        guard let target = focusedTarget() else { return }
        AccessibilityClient.toggleFullscreen(target.window)
    }

    // MARK: - 方向フォーカス移動

    // 指定方向にある最も近いウィンドウへフォーカスを移す。
    // 同一 Space 内の全ウィンドウ（全ディスプレイ分）を対象に位置関係で選ぶため、
    // 「同一画面の隣ウィンドウ → 無ければ隣ディスプレイのウィンドウ」が距離計算で
    // 自然にカスケードされる。Spaces 間移動は AX が現 Space しか見えないため非対応。
    static func focusDirection(_ direction: Direction) {
        // 基準中心（NS 座標, Y 上方向）。focus が無ければ main スクリーン中央を起点にする
        let origin: CGPoint
        let currentWindow = focusedTarget()?.window
        if let window = currentWindow, let axFrame = AccessibilityClient.getFrame(window) {
            let ns = NSScreen.convertFromAX(axFrame)
            origin = CGPoint(x: ns.midX, y: ns.midY)
        } else {
            guard let screen = NSScreen.main ?? NSScreen.screens.first else {
                Log.window.warning("利用可能なスクリーンがありません")
                return
            }
            origin = CGPoint(x: screen.frame.midX, y: screen.frame.midY)
        }

        guard let best = bestWindow(in: direction, from: origin, excluding: currentWindow) else {
            Log.window.debug("指定方向にフォーカス可能なウィンドウがありません: \(direction)")
            return
        }

        best.runningApp.activate()
        AccessibilityClient.raise(best.window)
        // raise 後に focused window を明示的に設定（複数ウィンドウを持つアプリ用）
        AccessibilityClient.setFocusedWindow(best.window, of: best.app)
    }

    private struct WindowCandidate {
        let window: AXUIElement
        let app: AXUIElement
        let runningApp: NSRunningApplication
    }

    // 方向軸への変位がわずかでも前方であることを要求する許容誤差（ピクセル）
    private static let directionTolerance: CGFloat = 1.0
    // 直交方向のズレに掛ける重み。同方向に並ぶウィンドウを優先させる
    private static let perpendicularWeight: CGFloat = 2.0

    // 指定方向にあるウィンドウのうち、軸方向に最も近く・直交方向のズレが小さいものを選ぶ
    private static func bestWindow(in direction: Direction, from origin: CGPoint, excluding current: AXUIElement?) -> WindowCandidate? {
        var best: WindowCandidate?
        var bestScore = CGFloat.greatestFiniteMagnitude

        for runningApp in NSWorkspace.shared.runningApplications where runningApp.activationPolicy == .regular {
            let appElement = AXUIElementCreateApplication(runningApp.processIdentifier)
            for window in AccessibilityClient.windows(of: appElement) {
                if let current, CFEqual(window, current) { continue }
                if !AccessibilityClient.isStandardWindow(window) { continue }
                if AccessibilityClient.isMinimized(window) { continue }
                guard let axFrame = AccessibilityClient.getFrame(window),
                      axFrame.width > 1, axFrame.height > 1 else { continue }

                let ns = NSScreen.convertFromAX(axFrame)
                let center = CGPoint(x: ns.midX, y: ns.midY)

                // along: 指定方向への変位（正で前方）、perp: 直交方向のズレ
                let along: CGFloat
                let perp: CGFloat
                switch direction {
                case .right: along = center.x - origin.x; perp = abs(center.y - origin.y)
                case .left:  along = origin.x - center.x; perp = abs(center.y - origin.y)
                case .up:    along = center.y - origin.y; perp = abs(center.x - origin.x)
                case .down:  along = origin.y - center.y; perp = abs(center.x - origin.x)
                }
                guard along > directionTolerance else { continue }

                let score = along + perpendicularWeight * perp
                if score < bestScore {
                    bestScore = score
                    best = WindowCandidate(window: window, app: appElement, runningApp: runningApp)
                }
            }
        }
        return best
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

    // snap 系の共通処理。compute は (NSScreen, padding, 現在の NSScreen 座標 frame)
    // を受け取って次の target rect を返す。巡回ロジックは compute 側で組む
    private static func snap(_ compute: (NSScreen, CGFloat, CGRect?) -> CGRect) {
        guard let target = focusedTarget() else { return }
        let screen = currentScreen(of: target.window)
        let padding = CGFloat(ConfigManager.shared.current.general.padding)

        // 現ウィンドウの NSScreen 座標 frame。slide の起点としても、巡回判定にも使う
        let currentNS: CGRect? = AccessibilityClient.getFrame(target.window)
            .map { NSScreen.convertFromAX($0) }

        let nsRect = compute(screen, padding, currentNS)
        let fromNS: CGRect? = currentNS

        // 先に実ウィンドウへ反映する。min size 制約のあるアプリでは target どおりに
        // ならないことがあるため、適用後の実 frame を読み直してプレビューの終端
        // 位置として渡す。こうしないとアニメと実ウィンドウのサイズがずれて見える
        let axRect = NSScreen.convertToAX(nsRect)
        applyFrame(axRect, to: target)

        let actualNS: CGRect = AccessibilityClient.getFrame(target.window)
            .map { NSScreen.convertFromAX($0) } ?? nsRect

        // autoHideAfter はスライドアニメ duration と一致させ、スライド完走と同時に
        // フェード退出が始まるようにする
        let animDur = ConfigManager.shared.current.general.animationDuration
        PreviewWindow.shared.show(at: actualNS, from: fromNS, autoHideAfter: animDur)
    }

    // MARK: - 位置ベースの状態判定
    //
    // サイズ制約のあるアプリ（GitHub Desktop / Unity Hub 等）でも巡回判定が成立する
    // よう、target との厳密一致ではなく「左／右カラムの開始位置」と「上／下端揃え」
    // で判断する。サイズ制約で window が padded の境界を超えて広がっていても、
    // 左端の位置を頼りに「どの半分／クォーターを意図したか」を判定できる

    private static let edgeTolerance: CGFloat = 10

    // 左カラム（minX = padded.minX）
    private static func atLeftColumn(_ current: CGRect, padded: CGRect) -> Bool {
        abs(current.minX - padded.minX) < edgeTolerance
    }

    // 右カラム（minX = 右半分の左端 ≒ padded の右半分の開始位置）
    private static func atRightColumn(_ current: CGRect, padded: CGRect, padding: CGFloat) -> Bool {
        let rightColumnStart = padded.minX + (padded.width + padding) / 2
        return abs(current.minX - rightColumnStart) < edgeTolerance
    }

    // 上端揃え（NS 座標は Y 上方向、上端 = maxY）
    private static func topAligned(_ current: CGRect, padded: CGRect) -> Bool {
        abs(current.maxY - padded.maxY) < edgeTolerance
    }

    private static func bottomAligned(_ current: CGRect, padded: CGRect) -> Bool {
        abs(current.minY - padded.minY) < edgeTolerance
    }

    // 右端揃え（最大化判定に使う）
    private static func rightAligned(_ current: CGRect, padded: CGRect) -> Bool {
        abs(current.maxX - padded.maxX) < edgeTolerance
    }

    // 上半分相当: 上端揃え + 下端非揃え + 左カラム + 右端揃え（全幅）
    // 下端非揃えで「最大化」と区別する
    private static func isAtTopHalfPosition(_ current: CGRect, screen: NSScreen, padding: CGFloat) -> Bool {
        let padded = screen.visibleFrame.insetBy(dx: padding, dy: padding)
        return atLeftColumn(current, padded: padded)
            && rightAligned(current, padded: padded)
            && topAligned(current, padded: padded)
            && !bottomAligned(current, padded: padded)
    }

    // 左半分相当: 左カラム + 上下端揃え + 右端非揃え（半幅）
    private static func isAtLeftHalf(_ current: CGRect, screen: NSScreen, padding: CGFloat) -> Bool {
        let padded = screen.visibleFrame.insetBy(dx: padding, dy: padding)
        return atLeftColumn(current, padded: padded)
            && topAligned(current, padded: padded)
            && bottomAligned(current, padded: padded)
            && !rightAligned(current, padded: padded)
    }

    // 右半分相当: 右カラム + 上下端揃え
    private static func isAtRightHalf(_ current: CGRect, screen: NSScreen, padding: CGFloat) -> Bool {
        let padded = screen.visibleFrame.insetBy(dx: padding, dy: padding)
        return atRightColumn(current, padded: padded, padding: padding)
            && topAligned(current, padded: padded)
            && bottomAligned(current, padded: padded)
    }

    // 「半幅であること」を !rightAligned で要求する。これがないと「上半分（全幅）」が
    // 左上 1/4 と誤判定され、snapToLeftHalf の巡回が「左上 → 左下」に飛んでしまう
    private static func isAtTopLeftQuarter(_ current: CGRect, screen: NSScreen, padding: CGFloat) -> Bool {
        let padded = screen.visibleFrame.insetBy(dx: padding, dy: padding)
        return atLeftColumn(current, padded: padded)
            && !rightAligned(current, padded: padded)
            && topAligned(current, padded: padded)
            && !bottomAligned(current, padded: padded)
    }

    private static func isAtBottomLeftQuarter(_ current: CGRect, screen: NSScreen, padding: CGFloat) -> Bool {
        let padded = screen.visibleFrame.insetBy(dx: padding, dy: padding)
        return atLeftColumn(current, padded: padded)
            && !rightAligned(current, padded: padded)
            && !topAligned(current, padded: padded)
            && bottomAligned(current, padded: padded)
    }

    // 右 1/4 は !atLeftColumn で「全幅でない」ことを担保する（左カラムと右カラムは
    // 半幅前提で互いに排他のため、これで十分）
    private static func isAtTopRightQuarter(_ current: CGRect, screen: NSScreen, padding: CGFloat) -> Bool {
        let padded = screen.visibleFrame.insetBy(dx: padding, dy: padding)
        return atRightColumn(current, padded: padded, padding: padding)
            && !atLeftColumn(current, padded: padded)
            && topAligned(current, padded: padded)
            && !bottomAligned(current, padded: padded)
    }

    private static func isAtBottomRightQuarter(_ current: CGRect, screen: NSScreen, padding: CGFloat) -> Bool {
        let padded = screen.visibleFrame.insetBy(dx: padding, dy: padding)
        return atRightColumn(current, padded: padded, padding: padding)
            && !atLeftColumn(current, padded: padded)
            && !topAligned(current, padded: padded)
            && bottomAligned(current, padded: padded)
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
