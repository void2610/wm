import AppKit

// 高レベルのウィンドウ操作 API。snap / maximize / center などを提供する。
// Phase 1 で本実装する。
enum WindowController {
    // 左半分にスナップする（プレースホルダ）
    static func snapToLeftHalf() {}

    // 右半分にスナップする（プレースホルダ）
    static func snapToRightHalf() {}

    // 上半分にスナップする（プレースホルダ）
    static func snapToTopHalf() {}

    // 下半分にスナップする（プレースホルダ）
    static func snapToBottomHalf() {}

    // 最大化する（visibleFrame 全体に拡大）
    static func maximize() {}

    // 画面中央に配置する
    static func center() {}

    // ネイティブのフルスクリーン状態をトグルする
    static func toggleFullscreen() {}
}
