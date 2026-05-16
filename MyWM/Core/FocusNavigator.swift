import AppKit
import ApplicationServices

// 方向キーでのフォーカス移動。
// 全アプリの全ウィンドウから現在の focused window 以外を集め、
// 中心座標が指定方向にあるものから「角度ペナルティ + 距離」で最良の 1 つを選ぶ。
enum FocusNavigator {

    enum Direction { case left, right, up, down }

    static func focus(_ direction: Direction) {
        guard let current = currentWindowFrame() else { return }
        let candidates = otherWindowsWithFrames(excluding: current.id)

        guard let best = pickBest(from: candidates, current: current.frame, direction: direction) else { return }

        // 対象アプリを activate してから window を raise する
        let pid = pidOfApp(best.app)
        if let pid, let runningApp = NSRunningApplication(processIdentifier: pid) {
            runningApp.activate(options: [.activateIgnoringOtherApps])
        }
        AccessibilityClient.raise(best.window)
    }

    // MARK: - 内部

    private struct CurrentWindow {
        let frame: CGRect
        let id: ObjectIdentifier? // AXUIElement は AnyObject だが、識別には pid+title 等が必要
    }

    private struct Candidate {
        let window: AXUIElement
        let app: AXUIElement
        let frame: CGRect
    }

    private static func currentWindowFrame() -> (frame: CGRect, id: ObjectIdentifier?)? {
        guard let window = AccessibilityClient.focusedWindow(),
              let frame = AccessibilityClient.getFrame(window) else { return nil }
        // AXUIElement は class type ではないため identity 比較は frame ベースで近似する
        return (frame, nil)
    }

    private static func otherWindowsWithFrames(excluding _: ObjectIdentifier?) -> [Candidate] {
        var result: [Candidate] = []
        let currentFrame = AccessibilityClient.focusedWindow().flatMap { AccessibilityClient.getFrame($0) }
        for (window, app) in AccessibilityClient.allWindows() {
            guard let frame = AccessibilityClient.getFrame(window) else { continue }
            // 自分自身は frame 完全一致で除外する近似
            if let cf = currentFrame, frame == cf { continue }
            // サイズ 0 のウィンドウ（最小化等）は除外
            if frame.width < 1 || frame.height < 1 { continue }
            result.append(Candidate(window: window, app: app, frame: frame))
        }
        return result
    }

    // 方向に対する最良候補を選ぶ。距離 + 方向ずれペナルティ
    private static func pickBest(from candidates: [Candidate], current: CGRect, direction: Direction) -> Candidate? {
        let cx = current.midX
        let cy = current.midY

        var best: Candidate?
        var bestScore = CGFloat.greatestFiniteMagnitude

        for c in candidates {
            let dx = c.frame.midX - cx
            let dy = c.frame.midY - cy

            // 方向に沿った主成分と直交成分
            let primary: CGFloat
            let cross: CGFloat
            switch direction {
            case .left:  primary = -dx; cross = abs(dy)
            case .right: primary = dx;  cross = abs(dy)
            case .up:    primary = -dy; cross = abs(dx)   // AX 座標は Y 下向きなので、上は dy が負
            case .down:  primary = dy;  cross = abs(dx)
            }
            // 指定方向の反対側にあるウィンドウは無視
            if primary <= 0 { continue }

            // 主軸距離が小さいほど良い。直交成分にはペナルティを乗せる
            let score = primary + cross * 2
            if score < bestScore {
                bestScore = score
                best = c
            }
        }
        return best
    }

    // app element から pid を取り出す
    private static func pidOfApp(_ app: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        let result = AXUIElementGetPid(app, &pid)
        return result == .success ? pid : nil
    }
}
