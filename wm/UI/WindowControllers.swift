import AppKit
import SwiftUI

// 設定 / Onboarding ウィンドウを表示するためのヘルパー。
//
// 一般の NSWindow を使うと、accessory（LSUIElement=YES）でも
// NSApp.activate と組み合わさったときに Dock アイコンが現れてしまうケースがある。
// これを避けるため両方とも .nonactivatingPanel な NSPanel を使う。
// nonactivatingPanel は表示しても app を active にしないため、accessory が崩れず
// Dock に出ない。代わりに orderFrontRegardless + makeKey で前面化する
@MainActor
enum AppWindows {
    private static var settingsController: NSWindowController?
    private static var onboardingController: NSWindowController?

    static func showSettings() {
        if let controller = settingsController, let window = controller.window {
            window.orderFrontRegardless()
            window.makeKey()
            return
        }
        let view = SettingsView()
        let host = NSHostingController(rootView: view)
        let panel = makePanel(
            title: "wm 設定",
            contentSize: NSSize(width: 560, height: 420),
            host: host
        )
        let controller = NSWindowController(window: panel)
        settingsController = controller
        controller.showWindow(nil)
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    static func showOnboarding(monitor: PermissionMonitor) {
        if let controller = onboardingController, let window = controller.window {
            window.orderFrontRegardless()
            window.makeKey()
            return
        }
        let view = OnboardingView(monitor: monitor)
        let host = NSHostingController(rootView: view)
        let panel = makePanel(
            title: "wm のセットアップ",
            contentSize: NSSize(width: 480, height: 280),
            host: host
        )
        let controller = NSWindowController(window: panel)
        onboardingController = controller
        controller.showWindow(nil)
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    static func closeOnboarding() {
        onboardingController?.close()
        onboardingController = nil
    }

    // NSPanel(.nonactivatingPanel) を共通で構築する。
    // becomesKeyOnlyIfNeeded = false にしないと SwiftUI の入力フォーカスが
    // 受け取れずキーボード操作不能になる
    private static func makePanel(
        title: String,
        contentSize: NSSize,
        host: NSHostingController<some View>
    ) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = title
        panel.contentViewController = host
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = false
        panel.collectionBehavior = [.fullScreenAuxiliary]
        panel.center()
        return panel
    }
}
