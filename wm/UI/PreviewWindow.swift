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
// - show のときだけ orderFrontRegardless し、フェード完了後に orderOut する。
//   常時 visible で画面上に存在させると、透明・mouseEvents 無視であってもシステムの Dock
//   自動非表示が抑制されて Dock が出っぱなしになるため
// - NSWindow.animator().setFrame で window 自身の frame を動かす方式は連続呼出時に
//   AppKit 側のアニメ状態が不安定になるため使わない。中の矩形（rect）を SwiftUI の
//   @Published + withAnimation で補間する
// - rect / isVisible のアニメは ConfigManager.animation_duration の有限時間 easeOut に揃え、
//   autoHide のタイミングをスライド完走と一致させる。spring は terminate 時刻が不確定で
//   スライドが終わる前に hide() が走るとフェード中もスライドが続いてしまうため使わない
@MainActor
final class PreviewWindow {
    static let shared = PreviewWindow()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<PreviewView>?
    private let viewModel = PreviewViewModel()
    private var autoHideWorkItem: DispatchWorkItem?
    // フェード退出完了後に panel を orderOut するためのワークアイテム。
    // 次回 show のときに必ずキャンセルする
    private var orderOutWorkItem: DispatchWorkItem?

    private init() {}

    // 現在の config から有限時間の easing を作る。
    // ここで使う duration が autoHideAfter とも揃うことで、スライド完走 → 即 hide が
    // 確定的なタイムラインとして組める
    private var slideAnim: Animation {
        Anim.snapSlide(duration: ConfigManager.shared.current.general.animationDuration)
    }

    // 指定 frame の位置にプレビューを表示する。引数は NSScreen グローバル座標。
    // from が指定されていれば、非表示状態からの初回出現を from→target のスライドで表現する。
    // 既に表示中なら from は無視して現在位置から target へ補間する。
    // autoHideAfter > 0 のときは指定秒後に自動 hide。連打時は前の自動 hide をキャンセル
    func show(at frame: CGRect, from startFrame: CGRect? = nil, autoHideAfter: TimeInterval = 0) {
        guard ConfigManager.shared.current.general.animationEnabled else { return }
        ensurePanel()

        autoHideWorkItem?.cancel()
        // 前回の hide で予約された orderOut を取り消す
        orderOutWorkItem?.cancel()

        // target rect を含むスクリーンを panel の表示先にする。from と target で
        // スクリーンが違う場合は target 側を優先する（snap は同一スクリーン内で
        // 完結する想定だが、念のため target 基準で揃える）
        let targetScreen = NSScreen.containing(point: CGPoint(x: frame.midX, y: frame.midY))
        let overlay = targetScreen.visibleFrame
        viewModel.overlayFrame = overlay
        if let panel = panel {
            panel.setFrame(overlay, display: panel.isVisible)
            if !panel.isVisible {
                panel.orderFrontRegardless()
            }
        }

        let anim = slideAnim

        if viewModel.isVisible {
            // 表示中: 現在の rect から target へ補間
            withAnimation(anim) {
                viewModel.rect = frame
            }
        } else {
            // 非表示状態: まず from（指定無ければ target）に瞬間配置 → 次の runloop で target へ補間。
            // 1 段階目を transaction(disablesAnimations) で囲むことで、startFrame への
            // 配置はアニメーションさせない
            let start = startFrame ?? frame
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                viewModel.rect = start
            }
            withAnimation(anim) {
                viewModel.isVisible = true
            }
            // 次の runloop tick で target へ。start が一度 render された後の差分が
            // withAnimation で補間されるため、見た目は from→target のスライドになる
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                withAnimation(self.slideAnim) {
                    self.viewModel.rect = frame
                }
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

    // プレビューを隠す（フェードアウト → 完了後に panel を orderOut）。
    // orderOut しないと panel が常時画面上に居続け、システムの Dock 自動非表示が
    // 抑制されてしまう
    func hide() {
        autoHideWorkItem?.cancel()
        let dur = ConfigManager.shared.current.general.animationDuration
        withAnimation(slideAnim) {
            viewModel.isVisible = false
        }
        // フェード完了後に panel を画面から外す
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.panel?.orderOut(nil) }
        }
        orderOutWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + dur, execute: item)
    }

    // 必要に応じて NSPanel を生成する。生成しただけでは画面に出さない。
    // 実際の表示と frame 反映は show() で行う
    private func ensurePanel() {
        if panel != nil { return }

        // 初期 frame は仮置き。show() で target スクリーンに合わせて毎回更新する
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

        let view = PreviewView(viewModel: viewModel)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: initial.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        hostingView = host

        panel.setFrame(initial, display: false)
        // ここでは orderFront しない。show() で必要なときに前面化する。
        // 常時 visible だと透明・mouseEvents 無視でもシステムの Dock 自動非表示が
        // 抑制されて Dock が出っぱなしになるため

        self.panel = panel
    }
}

// View に渡す状態。@Published で SwiftUI が変化に反応する
@MainActor
final class PreviewViewModel: ObservableObject {
    @Published var rect: CGRect = .zero
    @Published var isVisible: Bool = false
    // 現在 panel が乗っているスクリーンの visibleFrame（NSScreen グローバル座標）。
    // SwiftUI 側で rect をパネル内ローカル座標へ変換するのに使う
    @Published var overlayFrame: CGRect = .zero
}
