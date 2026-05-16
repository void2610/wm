import Foundation

// ホットキー → アクション の中継層。Command パターンで疎結合にしておき、
// CLI 連携（mywm focus left など）が来てもここで集約できるようにする。
enum Action: Equatable {
    case focus(FocusNavigator.Direction)
    case snapLeft, snapRight, snapTop, snapBottom
    case snapTopLeft, snapTopRight, snapBottomLeft, snapBottomRight
    case maximize, center, toggleFullscreen
    case launchApp(bundleId: String)
}

enum ActionDispatcher {
    static func dispatch(_ action: Action) {
        switch action {
        case .focus(let dir):
            FocusNavigator.focus(dir)
        case .snapLeft:
            WindowController.snapToLeftHalf()
        case .snapRight:
            WindowController.snapToRightHalf()
        case .snapTop:
            WindowController.snapToTopHalf()
        case .snapBottom:
            WindowController.snapToBottomHalf()
        case .snapTopLeft:
            WindowController.snapToTopLeftQuarter()
        case .snapTopRight:
            WindowController.snapToTopRightQuarter()
        case .snapBottomLeft:
            WindowController.snapToBottomLeftQuarter()
        case .snapBottomRight:
            WindowController.snapToBottomRightQuarter()
        case .maximize:
            WindowController.maximize()
        case .center:
            WindowController.center()
        case .toggleFullscreen:
            WindowController.toggleFullscreen()
        case .launchApp(let bundleId):
            AppLauncher.launch(bundleId: bundleId)
        }
    }
}
