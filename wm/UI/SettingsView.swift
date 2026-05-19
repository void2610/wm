import SwiftUI

// 設定画面。general セクションの値はここで編集可能で、変更は即座に
// ConfigManager.saveGeneral 経由で TOML に書き戻される。
// hotkeys / launch は TOML を正として GUI からは閲覧のみ
struct SettingsView: View {
    @State private var animationEnabled: Bool = ConfigManager.shared.current.general.animationEnabled
    @State private var animationDuration: Double = ConfigManager.shared.current.general.animationDuration
    @State private var padding: Int = ConfigManager.shared.current.general.padding
    @State private var hotkeys: [String: String] = ConfigManager.shared.current.hotkeys
    @State private var lastError: String? = ConfigManager.shared.lastError

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("一般", systemImage: "gearshape") }
            hotkeysTab
                .tabItem { Label("ホットキー", systemImage: "command") }
            aboutTab
                .tabItem { Label("wm について", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 420)
        .onAppear {
            reloadFromManager()
        }
    }

    private var generalTab: some View {
        Form {
            Toggle("アニメーションを有効にする", isOn: $animationEnabled)
                .onChange(of: animationEnabled) { _ in saveGeneral() }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("アニメーション時間")
                    Spacer()
                    Text(String(format: "%.2f 秒", animationDuration))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $animationDuration, in: 0.05...1.0, step: 0.05)
                    .onChange(of: animationDuration) { _ in saveGeneral() }
            }

            Stepper(value: $padding, in: 0...64, step: 1) {
                HStack {
                    Text("ウィンドウ間 padding")
                    Spacer()
                    Text("\(padding) px")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .onChange(of: padding) { _ in saveGeneral() }

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
                ForEach(hotkeys.keys.sorted(), id: \.self) { key in
                    HStack {
                        Text(key)
                        Spacer()
                        Text(hotkeys[key] ?? "")
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
            Text("wm")
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

    // ConfigManager.current から @State を読み直す
    private func reloadFromManager() {
        let cfg = ConfigManager.shared.current
        animationEnabled = cfg.general.animationEnabled
        animationDuration = cfg.general.animationDuration
        padding = cfg.general.padding
        hotkeys = cfg.hotkeys
        lastError = ConfigManager.shared.lastError
    }

    // general セクションを ConfigManager 経由で TOML に書き戻す
    private func saveGeneral() {
        var g = ConfigManager.shared.current.general
        g.animationEnabled = animationEnabled
        g.animationDuration = animationDuration
        g.padding = padding
        ConfigManager.shared.saveGeneral(g)
        lastError = ConfigManager.shared.lastError
    }
}
