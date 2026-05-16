import Foundation
import KeyboardShortcuts

// グローバルホットキーの登録・解除を担当する。Phase 1 で初期実装、
// Phase 2 で config 駆動に書き換える。
final class HotkeyManager {
    static let shared = HotkeyManager()

    private init() {}

    // 現在登録中の全ショートカットを解除する（reload 時に使う）
    func unregisterAll() {
        // Phase 2: KeyboardShortcuts のすべての onKeyDown を解除する
    }

    // config を元にホットキーを登録し直す
    func registerAll() {
        // Phase 2: Config をパースして登録する
    }
}

// KeyboardShortcuts.Name に独自ホットキー名を生やす
extension KeyboardShortcuts.Name {
    static let focusLeft = Self("focusLeft")
    static let focusRight = Self("focusRight")
    static let focusUp = Self("focusUp")
    static let focusDown = Self("focusDown")

    static let snapLeft = Self("snapLeft")
    static let snapRight = Self("snapRight")
    static let snapTop = Self("snapTop")
    static let snapBottom = Self("snapBottom")
    static let maximize = Self("maximize")
    static let center = Self("center")

    static let snapTopLeft = Self("snapTopLeft")
    static let snapTopRight = Self("snapTopRight")
    static let snapBottomLeft = Self("snapBottomLeft")
    static let snapBottomRight = Self("snapBottomRight")
}
