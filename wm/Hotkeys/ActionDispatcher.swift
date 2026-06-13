import Foundation

// ホットキー → アクション の中継層。Command パターンで疎結合にしておき、
// CLI 連携（wm focus left など）が来てもここで集約できるようにする。

// 方向フォーカス移動の方向
enum Direction: Equatable, CustomStringConvertible {
    case left, right, up, down

    var description: String {
        switch self {
        case .left: return "left"
        case .right: return "right"
        case .up: return "up"
        case .down: return "down"
        }
    }
}

enum Action: Equatable {
    case snapLeft, snapRight, snapTop, snapBottom
    case maximize, center, toggleFullscreen
    case focus(Direction)
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
        case .focus(let direction):
            WindowController.focusDirection(direction)
        case .launchApp(let bundleId):
            AppLauncher.launch(bundleId: bundleId)
        case .launchPath(let path):
            AppLauncher.launch(path: path)
        }
    }
}
