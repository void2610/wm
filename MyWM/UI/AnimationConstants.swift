import SwiftUI

// Loop/Luminare 的にアニメーション値を一箇所に集約する。
// プレビュー UI とメニュー UI のトーンを統一するための定数群
enum Anim {
    // プレビュー矩形のスライド / 出現 / 退出に使う。
    // spring は terminate 時刻が不確定で autoHide のタイミングと衝突するため
    // ConfigManager.animation_duration に正確に合致する有限時間 easing を使う。
    // duration はランタイムで設定値を読み出す
    static func snapSlide(duration: TimeInterval) -> Animation {
        .easeOut(duration: duration)
    }

    // メニュー出現のバネ（プレビューとは無関係なので spring のままで OK）
    static let menuAppear = Animation.spring(response: 0.28, dampingFraction: 0.8)
}
