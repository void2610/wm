import AppKit

// 方向キーでのフォーカス移動。全ウィンドウを座標ソートし、指定方向に最も近い
// ウィンドウへ AXRaise でフロントに引き上げる。Phase 1 で本実装する。
enum FocusNavigator {
    enum Direction { case left, right, up, down }

    static func focus(_ direction: Direction) {}
}
