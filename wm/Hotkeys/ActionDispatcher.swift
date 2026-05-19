import Foundation

// ホットキー → アクション の中継層。Command パターンで疎結合にしておき、
// CLI 連携（wm focus left など）が来てもここで集約できるようにする。
enum Action: Equatable {
    case snapLeft, snapRight, snapTop, snapBottom
    case maximize, center, toggleFullscreen
    case launchApp(bundleId: String)
    case launchPath(path: String)
}

@MainActor
enum ActionDispatcher {
    static func dispatch(_ action: Action) {
        switch action {
        case .snapLeft:
            WindowController.snapToLeftHalf()
        case .snapRight:
            WindowController.snapToRightHalf()
        case .snapTop:
            WindowController.snapToTopHalf()
        case .snapBottom:
            WindowController.snapToBottomHalf()
        case .maximize:
            WindowController.maximize()
        case .center:
            WindowController.center()
        case .toggleFullscreen:
            WindowController.toggleFullscreen()
        case .launchApp(let bundleId):
            AppLauncher.launch(bundleId: bundleId)
        case .launchPath(let path):
            AppLauncher.launch(path: path)
        }
    }
}
