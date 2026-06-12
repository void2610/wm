import Foundation

// ホットキー → アクション の中継層。Command パターンで疎結合にしておき、
// CLI 連携（wm focus left など）が来てもここで集約できるようにする。

// ディスプレイ間のフォーカス移動方向
enum Direction: Equatable {
    case left, right, up, down
}

enum Action: Equatable {
    case snapLeft, snapRight, snapTop, snapBottom
    case maximize, center, toggleFullscreen
    case focusDisplay(Direction)
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
        case .focusDisplay(let direction):
            WindowController.focusDisplay(direction: direction)
        case .launchApp(let bundleId):
            AppLauncher.launch(bundleId: bundleId)
        case .launchPath(let path):
            AppLauncher.launch(path: path)
        }
    }
}
