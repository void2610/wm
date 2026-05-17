import AppKit
import SwiftUI

// 設定 / Onboarding ウィンドウを表示するためのヘルパー。
// MenuBarExtra から呼ばれる前提で、シングルトンで管理する
@MainActor
enum AppWindows {
    private static var settingsController: NSWindowController?
    private static var onboardingController: NSWindowController?

    static func showSettings() {
        if let controller = settingsController {
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = SettingsView()
        let host = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: host)
        window.title = "wm 設定"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 560, height: 420))
        window.center()
        let controller = NSWindowController(window: window)
        settingsController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func showOnboarding(monitor: PermissionMonitor) {
        if let controller = onboardingController {
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = OnboardingView(monitor: monitor)
        let host = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: host)
        window.title = "wm のセットアップ"
        window.styleMask = [.titled, .closable]
        window.center()
        let controller = NSWindowController(window: window)
        onboardingController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func closeOnboarding() {
        onboardingController?.close()
        onboardingController = nil
    }
}
