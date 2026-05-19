import AppKit
import SwiftUI
import Combine

// スナップ先を予告する半透明ウィンドウ。
// 設計方針:
// - 複数ディスプレイ環境では、全スクリーン visibleFrame の union を覆う 1 つの NSPanel に
//   しても AppKit の制約で単一スクリーンに縮められたり、副ディスプレイ上に描画されない
//   ケースがある。そのため show() で渡された target rect を含むスクリーン 1 枚分だけを
//   その都度 panel の frame にし、SwiftUI 側ではパネル内ローカル座標に矩形を配置する方式に
//   している。スナップ操作はスクリーンを跨がない前提
// - フェード in/out は **panel.alphaValue** を自前 Timer で 60Hz 補間する。SwiftUI の
//   .opacity / withAnimation は連続 show / hide のタイミングで補間状態をリセットしにくく、
//   「アニメが終わった直後に次が始まると途中からしか見えない」症状を踏みやすい。
//   NSWindow.animator().alphaValue も CAAnimation が backing layer に attach されて
//   contentView.layer.removeAllAnimations() では止められないため、自前 Timer で
//   invalidate() ベースの確実な停止を可能にする
// - スライド（rect の補間）は SwiftUI 側で withAnimation する。これは中身の矩形の
//   位置補間で、panel 自体は動かさない
// - hide のフェードアウト完了後、orderOut は 2 秒遅延させる。直後に orderOut すると、
//   次の show での orderFrontRegardless 〜 最初の描画フレームに遅延が発生し、
//   フェードインの先頭が見えなくなる。連続 show 時には orderOutWorkItem.cancel() で
//   遅延 orderOut を取り消し、panel は alpha=0 のまま visible で残す。
//   2 秒経って show が来なければ orderOut して Dock 自動非表示の抑制を解除する
// - NSWindow.animator().setFrame で window 自身の frame を動かす方式は連続呼出時に
//   AppKit 側のアニメ状態が不安定になるため使わない
@MainActor
final class PreviewWindow {
    static let shared = PreviewWindow()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<PreviewView>?
    private let viewModel = PreviewViewModel()
    private var autoHideWorkItem: DispatchWorkItem?
    // フェード退出完了後に panel を orderOut するためのワークアイテム
    private var orderOutWorkItem: DispatchWorkItem?

    // alphaValue を自前で補間する Timer（invalidate() で確実に停止できる）
    private var fadeTimer: Timer?
    private var fadeStartTime: CFTimeInterval = 0
    private var fadeStartAlpha: CGFloat = 0
    private var fadeTargetAlpha: CGFloat = 0
    private var fadeDuration: TimeInterval = 0
    private var fadeOnFinish: (() -> Void)?

    private init() {}

    // alphaValue を from→to に easeOut で補間する。進行中の補間は強制停止して
    // 新しい補間で上書きする
    private func animateAlpha(from: CGFloat, to: CGFloat, duration: TimeInterval, onFinish: (() -> Void)? = nil) {
        fadeTimer?.invalidate()
        fadeTimer = nil
        guard let panel = panel else { onFinish?(); return }

        panel.alphaValue = from
        fadeStartTime = CACurrentMediaTime()
        fadeStartAlpha = from
        fadeTargetAlpha = to
        fadeDuration = duration
        fadeOnFinish = onFinish

        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel else { timer.invalidate(); return }
                let elapsed = CACurrentMediaTime() - self.fadeStartTime
                let t = min(max(elapsed / self.fadeDuration, 0), 1)
                // easeOut: 1 - (1 - t)^2
                let eased = 1 - (1 - t) * (1 - t)
                panel.alphaValue = self.fadeStartAlpha + (self.fadeTargetAlpha - self.fadeStartAlpha) * eased
                if t >= 1 {
                    timer.invalidate()
                    self.fadeTimer = nil
                    let cb = self.fadeOnFinish
                    self.fadeOnFinish = nil
                    cb?()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        fadeTimer = timer
    }

    // 現在の config から有限時間の easing を作る
    private var slideAnim: Animation {
        Anim.snapSlide(duration: ConfigManager.shared.current.general.animationDuration)
    }

    // 指定 frame の位置にプレビューを表示する。引数は NSScreen グローバル座標。
    // from が指定されていれば、from→target のスライドで表現する。
    // 既に表示中なら from は無視して現在位置から target へ補間する。
    // autoHideAfter > 0 のときは指定秒後に自動 hide。連打時は前の自動 hide をキャンセル
    func show(at frame: CGRect, from startFrame: CGRect? = nil, autoHideAfter: TimeInterval = 0) {
        guard ConfigManager.shared.current.general.animationEnabled else { return }
        ensurePanel()

        autoHideWorkItem?.cancel()
        orderOutWorkItem?.cancel()

        // target rect を含むスクリーンを panel の表示先にする
        let targetScreen = NSScreen.containing(point: CGPoint(x: frame.midX, y: frame.midY))
        let overlay = targetScreen.visibleFrame
        viewModel.overlayFrame = overlay

        guard let panel = panel else { return }

        panel.setFrame(overlay, display: panel.isVisible)

        let dur = ConfigManager.shared.current.general.animationDuration
        let currentAlpha = panel.alphaValue
        let isCompletelyHidden = !panel.isVisible || (currentAlpha < 0.001 && fadeTimer == nil)

        if isCompletelyHidden {
            // 完全に消えた状態（初回 or hide 完了後）からの出現。
            fadeTimer?.invalidate()
            fadeTimer = nil
            if !panel.isVisible {
                panel.orderFrontRegardless()
            }
            let start = startFrame ?? frame
            // generation を inc して view ツリーを再生成し、SwiftUI の補間器を
            // 完全にリセットする。同時に rect も start に確定配置
            viewModel.generation &+= 1
            var resetTx = Transaction()
            resetTx.disablesAnimations = true
            withTransaction(resetTx) {
                viewModel.rect = start
            }
            hostingView?.layoutSubtreeIfNeeded()
            panel.alphaValue = 0
            panel.displayIfNeeded()

            // 1 フレーム以上待ってから補間を発火する。DispatchQueue.main.async では
            // 同 runloop iteration 内で消化されることがあり、SwiftUI が rect=start を
            // 1 度も描画しないまま rect=frame の withAnimation を受け取ると
            // 「前回 target → frame」の補間に潰れて start→frame のスライドが消える
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0 / 60.0) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.animateAlpha(from: 0, to: 1, duration: dur)
                    withAnimation(self.slideAnim) {
                        self.viewModel.rect = frame
                    }
                }
            }
        } else {
            // 既に何かしら見えている状態（完全表示 or フェード中）。
            // alpha は現在値から 1 に「中断・反転」させ、rect は現在値から target へ補間する。
            // これにより panel が一瞬消えるような切れ目が出ず、滑らかに次のアニメに繋がる
            animateAlpha(from: currentAlpha, to: 1, duration: dur)
            withAnimation(slideAnim) {
                viewModel.rect = frame
            }
        }

        if autoHideAfter > 0 {
            let item = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.hide() }
            }
            autoHideWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + autoHideAfter, execute: item)
        }
    }

    // プレビューを隠す（panel.alphaValue でフェードアウト → 完了後 2 秒遅延で orderOut）。
    // orderOut を遅延させる理由はファイル冒頭コメント参照
    func hide() {
        autoHideWorkItem?.cancel()
        orderOutWorkItem?.cancel()
        guard let panel = panel else { return }
        let dur = ConfigManager.shared.current.general.animationDuration

        animateAlpha(from: panel.alphaValue, to: 0, duration: dur) { [weak self] in
            let delayed = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    self?.panel?.orderOut(nil)
                }
            }
            self?.orderOutWorkItem = delayed
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: delayed)
        }
    }

    // 必要に応じて NSPanel を生成する。生成しただけでは画面に出さない。
    private func ensurePanel() {
        if panel != nil { return }

        let initial = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero

        let panel = NSPanel(
            contentRect: initial,
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
        panel.alphaValue = 0

        let view = PreviewView(viewModel: viewModel)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: initial.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        hostingView = host

        panel.setFrame(initial, display: false)

        self.panel = panel
    }
}

// View に渡す状態。@Published で SwiftUI が変化に反応する
@MainActor
final class PreviewViewModel: ObservableObject {
    @Published var rect: CGRect = .zero
    // 現在 panel が乗っているスクリーンの visibleFrame（NSScreen グローバル座標）
    @Published var overlayFrame: CGRect = .zero
    // show() のたびに inc される世代カウンタ。PreviewView の .id() に渡すことで
    // SwiftUI の補間器・@State を完全リセットし、前回 show の補間状態を持ち越さない
    @Published var generation: Int = 0
}
