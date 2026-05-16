import AppKit
import SwiftUI

// スナップ先を予告する半透明ウィンドウ。Phase 4 で本実装する。
// NSPanel ベースで非アクティベート・非フォーカス・.statusBar レベル。
final class PreviewWindow {
    static let shared = PreviewWindow()

    private init() {}

    // 指定 frame の位置にプレビューを表示する
    func show(at frame: CGRect) {
        // Phase 4: NSPanel + SwiftUI で実装する
    }

    // プレビューを隠す
    func hide() {
        // Phase 4: フェードアウトしてから close する
    }
}
