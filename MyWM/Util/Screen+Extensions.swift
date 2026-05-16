import AppKit

// NSScreen の便利メソッド。visibleFrame からの分割枠を計算する。
extension NSScreen {
    // ウィンドウ中心座標が属するスクリーンを返す。見つからなければ main を返す
    static func containing(point: CGPoint) -> NSScreen {
        for screen in NSScreen.screens where screen.frame.contains(point) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    // padding を考慮して左半分の frame を返す
    func leftHalfFrame(padding: CGFloat = 0) -> CGRect {
        let f = visibleFrame
        let half = (f.width - padding) / 2
        return CGRect(x: f.minX, y: f.minY, width: half, height: f.height)
    }

    // padding を考慮して右半分の frame を返す
    func rightHalfFrame(padding: CGFloat = 0) -> CGRect {
        let f = visibleFrame
        let half = (f.width - padding) / 2
        return CGRect(x: f.minX + half + padding, y: f.minY, width: half, height: f.height)
    }
}
