import SwiftUI

// アプリのエントリポイント。Dock は出さずに menu bar に常駐する。
// Info.plist の LSUIElement は使わない（SwiftUI のシーン初期化が壊れて NSStatusItem が
// 表示されなくなる症状が出るため）。代わりに AppDelegate 側で
// NSApp.setActivationPolicy(.accessory) を呼んで Dock を非表示にする。
// SwiftUI のライフサイクル維持のためにダミーの WindowGroup を 1 つ持ち、
// 出現直後に hide する。
@main
struct MyWMApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            HiddenLifecycleView()
                .frame(width: 0, height: 0)
                .onAppear {
                    // 起動時に出現するダミーウィンドウを即座に隠す
                    if let window = NSApplication.shared.windows.first {
                        window.setIsVisible(false)
                        window.close()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 1, height: 1)
    }
}

// SwiftUI ライフサイクル維持のためのプレースホルダ View
private struct HiddenLifecycleView: View {
    var body: some View {
        EmptyView()
    }
}
