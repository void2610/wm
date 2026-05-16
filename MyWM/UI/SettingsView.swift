import SwiftUI

// 設定画面。ホットキーの編集は TOML を正とするため GUI からは閲覧と「config を開く」「reload」が中心。
// general セクションのトグル / 数値だけ即時反映するためにバインドして書き戻すのが Phase 5.x の宿題。
struct SettingsView: View {
    @State private var config: Config = ConfigManager.shared.current
    @State private var lastError: String? = ConfigManager.shared.lastError

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("一般", systemImage: "gearshape") }
            hotkeysTab
                .tabItem { Label("ホットキー", systemImage: "command") }
            aboutTab
                .tabItem { Label("MyWM について", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 420)
        .onAppear {
            reloadFromManager()
        }
    }

    private var generalTab: some View {
        Form {
            Toggle("アニメーションを有効にする", isOn: .constant(config.general.animationEnabled))
                .disabled(true)
            HStack {
                Text("アニメーション時間")
                Spacer()
                Text(String(format: "%.2f 秒", config.general.animationDuration))
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("ウィンドウ間 padding")
                Spacer()
                Text("\(config.general.padding) px")
                    .foregroundStyle(.secondary)
            }
            if let lastError {
                Section("設定エラー") {
                    Text(lastError)
                        .foregroundStyle(.red)
                        .font(.system(.callout, design: .monospaced))
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var hotkeysTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ホットキーは TOML ファイルで編集してください。")
                .foregroundStyle(.secondary)
            List {
                ForEach(config.hotkeys.keys.sorted(), id: \.self) { key in
                    HStack {
                        Text(key)
                        Spacer()
                        Text(config.hotkeys[key] ?? "")
                            .foregroundStyle(.secondary)
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }
            HStack {
                Button("config を開く") {
                    NSWorkspace.shared.open(ConfigManager.configPath)
                }
                Button("再読み込み") {
                    ConfigManager.shared.reload()
                    reloadFromManager()
                }
            }
        }
        .padding()
    }

    private var aboutTab: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.split.2x1")
                .font(.system(size: 56))
            Text("MyWM")
                .font(.title)
                .bold()
            Text("macOS 向けキーボード中心のウィンドウマネージャー")
                .foregroundStyle(.secondary)
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                Text("バージョン \(version)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Link("GitHub", destination: URL(string: "https://github.com/void2610/wm")!)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func reloadFromManager() {
        config = ConfigManager.shared.current
        lastError = ConfigManager.shared.lastError
    }
}
