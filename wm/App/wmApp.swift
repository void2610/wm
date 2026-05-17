import SwiftUI

// アプリのエントリポイント。Dock は出さずに menu bar に常駐する。
// Info.plist の LSUIElement=YES で accessory として起動する。
// SwiftUI のライフサイクル維持のためにダミーの WindowGroup を 1 つ持ち、
// 出現直後に hide する（LSUIElement=YES でも WindowGroup の初期ウィンドウは
// 一瞬出ようとするため明示的に close する）。
@main
struct wmApp: App {
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
