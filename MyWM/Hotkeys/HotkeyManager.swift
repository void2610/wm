import AppKit
import KeyboardShortcuts

// グローバルホットキーの登録・解除を担当する。
// Config の hotkeys セクションと launch セクションから動的に Name を生成して登録する。
final class HotkeyManager {
    static let shared = HotkeyManager()

    private var registeredNames: [KeyboardShortcuts.Name] = []

    private init() {}

    // ConfigManager を購読し、起動時 / 変更時に再登録する
    func attachToConfig() {
        ConfigManager.shared.onChange = { [weak self] config in
            self?.applyConfig(config)
        }
        applyConfig(ConfigManager.shared.current)
    }

    // 現在登録中の全ショートカットを解除する
    func unregisterAll() {
        // すべての onKeyDown ハンドラを解除
        KeyboardShortcuts.removeAllHandlers()
        // 登録した Name のショートカット割り当てを nil に戻す
        for name in registeredNames {
            KeyboardShortcuts.setShortcut(nil, for: name)
        }
        registeredNames.removeAll()
    }

    // config を元にホットキーを登録し直す
    func applyConfig(_ config: Config) {
        unregisterAll()

        // hotkeys セクション
        for (key, shortcutString) in config.hotkeys {
            guard let action = Config.action(forHotkeyKey: key) else {
                Log.hotkey.warning("未対応のホットキー名: \(key)")
                continue
            }
            register(name: "hotkey_\(key)", shortcutString: shortcutString) {
                ActionDispatcher.dispatch(action)
            }
        }

        // launch セクション
        for (index, launch) in config.launch.enumerated() {
            let action = Action.launchApp(bundleId: launch.bundleId)
            register(name: "launch_\(index)", shortcutString: launch.key) {
                ActionDispatcher.dispatch(action)
            }
        }

        Log.hotkey.info("ホットキー登録完了: \(self.registeredNames.count) 件")
    }

    // 名前と TOML 文字列から実際に Shortcut を割り当てる
    private func register(name nameString: String, shortcutString: String, action: @escaping () -> Void) {
        guard let shortcut = ShortcutParser.parse(shortcutString) else {
            Log.hotkey.warning("ショートカットのパースに失敗: \(nameString) = \(shortcutString)")
            return
        }
        let name = KeyboardShortcuts.Name(nameString)
        KeyboardShortcuts.setShortcut(shortcut, for: name)
        KeyboardShortcuts.onKeyDown(for: name, action: action)
        registeredNames.append(name)
    }
}
