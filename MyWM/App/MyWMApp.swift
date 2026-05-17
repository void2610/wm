import SwiftUI

// アプリのエントリポイント。LSUIElement = YES のメニューバー常駐アプリ。
// MenuBarExtra Scene は LSUIElement との組み合わせで表示されないケースがあるため、
// menu bar item は AppDelegate で NSStatusItem を直接生成する。
// ここの Scene は SwiftUI ライフサイクル維持のためのプレースホルダ。
@main
struct MyWMApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
