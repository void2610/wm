import SwiftUI

// Loop/Luminare 的にアニメーション値を一箇所に集約する。
// プレビュー UI とメニュー UI のトーンを統一するための定数群。
enum Anim {
    // スナップ確定時のメインのバネアニメ
    static let snapSpring = Animation.spring(response: 0.35, dampingFraction: 0.75)

    // プレビューのフェードイン / アウト
    static let previewFade = Animation.easeOut(duration: 0.18)

    // メニュー出現のバネ
    static let menuAppear = Animation.spring(response: 0.28, dampingFraction: 0.8)
}
