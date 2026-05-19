import AppKit
import SwiftUI
import Combine

// スナップ先を予告する半透明ウィンドウ。
// 設計方針:
// - NSPanel は visibleFrame の union を覆う透明オーバーレイ。show のときだけ
//   orderFrontRegardless し、フェード完了後に orderOut する。常時 visible で
//   画面上に存在させると、透明・mouseEvents 無視であってもシステムの Dock
//   自動非表示が抑制されて Dock が出っぱなしになるため。
//   NSWindow.animator().setFrame で window 自身の frame を動かす方式は連続呼出時に
//   AppKit 側のアニメ状態が不安定になるため使わない。
// - 中の矩形（rect）を SwiftUI の @Published + withAnimation で補間する。
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
    // ディスプレイ構成変更を監視するための observer。ホットプラグ後にも
    // overlay frame を全スクリーンの union に追従させる
    private var screenChangeObserver: NSObjectProtocol?

    private init() {}

    deinit {
        if let obs = screenChangeObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

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
        // 前回の hide で予約された orderOut を取り消し、orderOut 状態なら今すぐ前面化
        orderOutWorkItem?.cancel()
        if let panel = panel, !panel.isVisible {
            panel.orderFrontRegardless()
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
    // 実際の表示は show() の orderFrontRegardless で行う
    private func ensurePanel() {
        if panel != nil { return }

        let overlay = Self.overlayFrame()
        viewModel.overlayFrame = overlay

        // NSPanel は constrainFrameRect で単一スクリーンに収まるよう自動制約される。
        // 全スクリーンの union を覆いたいので、サブクラスでこれを無効化する
        let panel = OverlayPanel(
            contentRect: overlay,
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
        host.frame = NSRect(origin: .zero, size: overlay.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        hostingView = host

        panel.setFrame(overlay, display: false)
        // ここでは orderFront しない。show() で必要なときに前面化する。
        // 常時 visible だと透明・mouseEvents 無視でもシステムの Dock 自動非表示が
        // 抑制されて Dock が出っぱなしになるため

        self.panel = panel

        // ディスプレイ構成変更（接続 / 切断 / 解像度変更）に追従する
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateOverlayForScreens() }
        }
    }

    // ディスプレイ構成が変わったときに、panel の frame と viewModel が保持する
    // overlay frame を再計算する
    private func updateOverlayForScreens() {
        guard let panel = panel else { return }
        let overlay = Self.overlayFrame()
        viewModel.overlayFrame = overlay
        panel.setFrame(overlay, display: panel.isVisible)
    }

    // 全 NSScreen の visibleFrame を union したオーバーレイ frame（NSScreen グローバル座標）。
    // screen.frame ではなく visibleFrame を使うことで Dock とメニューバー領域には
    // 被せず、Dock の自動非表示が機能するようにする
    private static func overlayFrame() -> CGRect {
        NSScreen.screens.reduce(CGRect.null) { acc, screen in acc.union(screen.visibleFrame) }
    }
}

// View に渡す状態。@Published で SwiftUI が変化に反応する
@MainActor
final class PreviewViewModel: ObservableObject {
    @Published var rect: CGRect = .zero
    @Published var isVisible: Bool = false
    // 全スクリーン visibleFrame の union（NSScreen グローバル座標）。
    // SwiftUI 側で rect をパネル内ローカル座標へ変換するのに使う。
    // ディスプレイ構成変更でも更新する
    @Published var overlayFrame: CGRect = .zero
}

// NSPanel は通常、constrainFrameRect で「ウィンドウの属する単一スクリーンに
// 収まる」よう自動的に frame を縮められる。全スクリーン visibleFrame の union を
// 覆う透明オーバーレイとして使いたいので、この制約を無効化する。
// これをやらないと、複数ディスプレイ環境でメインディスプレイ 1 枚分にしか
// パネルが広がらず、副ディスプレイ側でプレビュー矩形が見えなくなる
final class OverlayPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
