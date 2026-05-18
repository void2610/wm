import SwiftUI

// アプリのエントリポイント。Dock は出さずに menu bar に常駐する。
// Info.plist の LSUIElement=YES + AppDelegate の setActivationPolicy(.accessory) で
// accessory として起動する。
//
// SwiftUI の Scene は Settings シーンを使う。WindowGroup は起動時に 1 度ダミー
// ウィンドウを生成して即座に閉じる必要があり、その瞬間に Dock アイコンが
// 一瞬チラついたり常駐したりするため避ける。Settings シーンはユーザーが明示的に
// 開かない限り window を作らないので、起動時にウィンドウが一切現れない。
// 実際の設定 UI は AppWindows.showSettings 経由で AppKit の NSPanel として表示する
@main
struct wmApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
