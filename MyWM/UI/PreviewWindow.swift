import AppKit
import SwiftUI

// スナップ先を予告する半透明ウィンドウ。
// NSPanel ベースで非アクティベート・非フォーカス・.statusBar レベル。
// SwiftUI 側で scale + opacity の spring アニメ、frame 変更は AppKit の animator() に任せる。
@MainActor
final class PreviewWindow {
    static let shared = PreviewWindow()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<PreviewView>?
    private var state = PreviewState()
    private var hideWorkItem: DispatchWorkItem?

    private init() {}

    // 指定 frame の位置にプレビューを表示する。引数は NSScreen 座標
    func show(at frame: CGRect) {
        // アニメーション無効時はそもそも何もしない
        guard ConfigManager.shared.current.general.animationEnabled else { return }

        ensurePanel()
        guard let panel else { return }

        hideWorkItem?.cancel()

        if panel.isVisible {
            // 既に表示中ならフレーム遷移を AppKit のアニメで補間
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = ConfigManager.shared.current.general.animationDuration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            // 初回表示。少し小さい位置からフェードイン感を出すため frame をセットしてから order
            panel.setFrame(frame, display: false)
            panel.orderFrontRegardless()
        }

        // SwiftUI 側のフラグを立てて scale + opacity アニメ
        state.isVisible = true
    }

    // プレビューを隠す
    func hide() {
        guard let panel else { return }
        state.isVisible = false
        // フェードアウト分の時間を待ってから window を閉じる
        let item = DispatchWorkItem { [weak self] in
            self?.panel?.orderOut(nil)
        }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
    }

    // 必要に応じて NSPanel を生成する
    private func ensurePanel() {
        if panel != nil { return }

        let view = PreviewView(isVisible: false)
        let host = NSHostingView(rootView: view)
        hostingView = host

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.contentView = host

        // 状態オブジェクトの変化を受けて hosting の rootView を更新する
        state.binding = { [weak self] visible in
            self?.hostingView?.rootView = PreviewView(isVisible: visible)
        }

        self.panel = panel
    }

    // SwiftUI に直接 ObservableObject を渡さず、コールバックで再描画させるためのシム
    private struct PreviewState {
        var isVisible: Bool = false {
            didSet { binding?(isVisible) }
        }
        var binding: ((Bool) -> Void)?
    }
}
