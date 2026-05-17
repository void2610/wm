import AppKit

// NSScreen ↔ AX 座標変換のためのユーティリティ。
// - AppKit (NSScreen): primary display の左下が原点、Y は上方向
// - Accessibility API: primary display の左上が原点、Y は下方向
extension NSScreen {

    // primary display （メニューバーがある画面 = NSScreen.screens.first）の高さ
    static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? NSScreen.main?.frame.height ?? 0
    }

    // NSScreen 座標の矩形を AX 座標（top-left 原点）に変換する
    static func convertToAX(_ rect: CGRect) -> CGRect {
        let y = primaryHeight - rect.origin.y - rect.height
        return CGRect(x: rect.origin.x, y: y, width: rect.width, height: rect.height)
    }

    // AX 座標の点を NSScreen 座標に変換する
    static func convertFromAX(_ point: CGPoint, height: CGFloat = 0) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y - height)
    }

    // AX 座標の矩形（top-left 原点）を NSScreen 座標に変換する
    static func convertFromAX(_ rect: CGRect) -> CGRect {
        let y = primaryHeight - rect.origin.y - rect.height
        return CGRect(x: rect.origin.x, y: y, width: rect.width, height: rect.height)
    }

    // 指定された NSScreen 座標の点を含むスクリーンを返す
    static func containing(point: CGPoint) -> NSScreen {
        for screen in NSScreen.screens where screen.frame.contains(point) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    // AX 座標の点を含むスクリーンを返す
    static func containingAX(point: CGPoint) -> NSScreen {
        containing(point: convertFromAX(point, height: 0))
    }

    // MARK: - 分割枠の計算 (戻り値は NSScreen 座標)

    // visibleFrame を padding で内側に縮め、上下左右で半分／4分割した枠を返す
    func paddedVisibleFrame(padding: CGFloat) -> CGRect {
        visibleFrame.insetBy(dx: padding, dy: padding)
    }

    func leftHalf(padding: CGFloat) -> CGRect {
        let f = paddedVisibleFrame(padding: padding)
        let w = (f.width - padding) / 2
        return CGRect(x: f.minX, y: f.minY, width: w, height: f.height)
    }

    func rightHalf(padding: CGFloat) -> CGRect {
        let f = paddedVisibleFrame(padding: padding)
        let w = (f.width - padding) / 2
        return CGRect(x: f.minX + w + padding, y: f.minY, width: w, height: f.height)
    }

    func topHalf(padding: CGFloat) -> CGRect {
        let f = paddedVisibleFrame(padding: padding)
        let h = (f.height - padding) / 2
        return CGRect(x: f.minX, y: f.minY + h + padding, width: f.width, height: h)
    }

    func bottomHalf(padding: CGFloat) -> CGRect {
        let f = paddedVisibleFrame(padding: padding)
        let h = (f.height - padding) / 2
        return CGRect(x: f.minX, y: f.minY, width: f.width, height: h)
    }

    func topLeftQuarter(padding: CGFloat) -> CGRect {
        let f = paddedVisibleFrame(padding: padding)
        let w = (f.width - padding) / 2
        let h = (f.height - padding) / 2
        return CGRect(x: f.minX, y: f.minY + h + padding, width: w, height: h)
    }

    func topRightQuarter(padding: CGFloat) -> CGRect {
        let f = paddedVisibleFrame(padding: padding)
        let w = (f.width - padding) / 2
        let h = (f.height - padding) / 2
        return CGRect(x: f.minX + w + padding, y: f.minY + h + padding, width: w, height: h)
    }

    func bottomLeftQuarter(padding: CGFloat) -> CGRect {
        let f = paddedVisibleFrame(padding: padding)
        let w = (f.width - padding) / 2
        let h = (f.height - padding) / 2
        return CGRect(x: f.minX, y: f.minY, width: w, height: h)
    }

    func bottomRightQuarter(padding: CGFloat) -> CGRect {
        let f = paddedVisibleFrame(padding: padding)
        let w = (f.width - padding) / 2
        let h = (f.height - padding) / 2
        return CGRect(x: f.minX + w + padding, y: f.minY, width: w, height: h)
    }

    func centeredFrame(size: CGSize) -> CGRect {
        let f = visibleFrame
        return CGRect(
            x: f.midX - size.width / 2,
            y: f.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
