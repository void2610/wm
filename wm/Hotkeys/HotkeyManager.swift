import AppKit
import KeyboardShortcuts

// グローバルホットキーの登録・解除を担当する。
// Config の hotkeys セクションと launch セクションから動的に Name を生成して登録する。
// KeyboardShortcuts のハンドラはイベント機構の都合で nonisolated なので、ハンドラ内で
// MainActor.assumeIsolated にラップしてから ActionDispatcher へ流す。
@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    private var registeredNames: [KeyboardShortcuts.Name] = []

    private init() {}

    // ConfigManager を購読し、起動時 / 変更時に再登録する
    func attachToConfig() {
        ConfigManager.shared.onChange = { [weak self] config in
            // onChange は main queue で呼ばれる前提
            MainActor.assumeIsolated {
                self?.applyConfig(config)
            }
        }
        applyConfig(ConfigManager.shared.current)
    }

    // 現在登録中の全ショートカットを解除する
    func unregisterAll() {
        KeyboardShortcuts.removeAllHandlers()
        for name in registeredNames {
            KeyboardShortcuts.setShortcut(nil, for: name)
        }
        registeredNames.removeAll()
    }

    // config を元にホットキーを登録し直す
    func applyConfig(_ config: Config) {
        unregisterAll()

        for (key, shortcutString) in config.hotkeys {
            guard let action = Config.action(forHotkeyKey: key) else {
                Log.hotkey.warning("未対応のホットキー名: \(key)")
                continue
            }
            register(name: "hotkey_\(key)", shortcutString: shortcutString, action: action)
        }

        for (index, launch) in config.launch.enumerated() {
            // bundle_id が指定されていれば .app 起動、なければ path 起動
            let action: Action
            if let bundleId = launch.bundleId, !bundleId.isEmpty {
                action = .launchApp(bundleId: bundleId)
            } else if let path = launch.path, !path.isEmpty {
                action = .launchPath(path: path)
            } else {
                Log.hotkey.warning("launch エントリに bundle_id / path のどちらも指定されていません: \(launch.key)")
                continue
            }
            register(name: "launch_\(index)", shortcutString: launch.key, action: action)
        }

        Log.hotkey.info("ホットキー登録完了: \(self.registeredNames.count) 件")
    }

    // 名前と TOML 文字列から実際に Shortcut を割り当て、Action を実行するハンドラを差し込む
    private func register(name nameString: String, shortcutString: String, action: Action) {
        guard let shortcut = ShortcutParser.parse(shortcutString) else {
            Log.hotkey.warning("ショートカットのパースに失敗: \(nameString) = \(shortcutString)")
            return
        }
        let name = KeyboardShortcuts.Name(nameString)
        KeyboardShortcuts.setShortcut(shortcut, for: name)
        KeyboardShortcuts.onKeyDown(for: name) {
            // KeyboardShortcuts は main thread でハンドラを呼ぶ前提
            MainActor.assumeIsolated {
                ActionDispatcher.dispatch(action)
            }
        }
        registeredNames.append(name)
    }
}
