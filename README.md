# wm

macOS 向けキーボード中心のウィンドウマネージャー。
AeroSpace ライクな機能セット + Loop ライクなアニメーション品質を目指した個人開発プロジェクト。

## 主な機能

- **ウィンドウスナップ**: 半分（左/右/上/下）、1/4 分割（左上/右上/左下/右下）、最大化、中央寄せ、フルスクリーン切替
- **方向フォーカス移動**: 全アプリの全ウィンドウから方向に応じて最適な 1 つを選んで前面化
- **アプリ起動ホットキー**: bundle id 指定。既に起動済みなら activate
- **TOML 設定**: `~/.config/mywm/config.toml` に集約。`XDG_CONFIG_HOME` 尊重・dotfiles 対応
- **ホットリロード**: ファイル変更を検知して自動再読み込み（デバウンス付き）
- **プレビュー UI**: スナップ先を半透明ウィンドウで予告（SwiftUI の spring アニメ）
- **`AXEnhancedUserInterface`**: Electron/Firefox/Notion 等のリサイズスムージング。bundle id 単位の除外設定あり

## 非ゴール

- tiling WM ではない（Rectangle + ランチャー的立ち位置）
- SIP 無効化を要求しない（yabai 系の private API は使わない）
- マルチデスクトップ管理は対象外（単一スペース前提）

## 動作要件

- macOS 13 以降
- Xcode 15 以降（ビルド時）
- アクセシビリティ権限の許可

## ビルド方法

### ローカル

```sh
# プロジェクトファイルを再生成（依存追加時など）
nix-shell -p xcodegen --run "xcodegen generate"

# ビルド
xcodebuild -project MyWM.xcodeproj -scheme MyWM -configuration Debug build
```

### CI 成果物のダウンロード

main へ push するたびに [GitHub Actions](https://github.com/void2610/wm/actions) で Release ビルドが走り、`.app` を zip にして artifact としてアップロードします。

1. Actions タブから直近の成功 run を開く
2. 下部 *Artifacts* セクションの `MyWM-<short-sha>` をダウンロード
3. zip を展開 → `MyWM.app` を `/Applications` などに配置

Ad-hoc 署名された .app ですが Developer ID 署名ではないため、初回起動時に Gatekeeper の警告が出ます。Finder で `MyWM.app` を右クリック → 開く → 警告ダイアログから「開く」で起動できます。

起動するとアクセシビリティ権限の案内ウィンドウが出るので、システム設定 > プライバシーとセキュリティ > アクセシビリティ で MyWM を ON にしてください。1〜2 秒で自動的にメニューバーアプリに切り替わります。

## 設定例

`~/.config/mywm/config.toml`:

```toml
[general]
animation_enabled = true
animation_duration = 0.25
padding = 8
enhanced_ui_excluded = ["com.apple.dt.Xcode"]

[hotkeys]
focus_left  = "cmd+opt+left"
focus_right = "cmd+opt+right"
focus_up    = "cmd+opt+up"
focus_down  = "cmd+opt+down"

snap_left   = "cmd+ctrl+left"
snap_right  = "cmd+ctrl+right"
snap_top    = "cmd+ctrl+up"
snap_bottom = "cmd+ctrl+down"
maximize    = "cmd+ctrl+return"
center      = "cmd+ctrl+c"

snap_top_left     = "cmd+ctrl+shift+left"
snap_top_right    = "cmd+ctrl+shift+right"
snap_bottom_left  = "cmd+opt+shift+left"
snap_bottom_right = "cmd+opt+shift+right"

[[launch]]
key = "cmd+shift+1"
bundle_id = "com.apple.Safari"

[[launch]]
key = "cmd+shift+2"
bundle_id = "com.googlecode.iterm2"
```

利用可能な hotkey 名:
- `focus_left` / `focus_right` / `focus_up` / `focus_down`
- `snap_left` / `snap_right` / `snap_top` / `snap_bottom`
- `snap_top_left` / `snap_top_right` / `snap_bottom_left` / `snap_bottom_right`
- `maximize` / `center` / `toggle_fullscreen`

モディファイア表記: `cmd` / `opt` / `ctrl` / `shift`（区切りは `+` または `-`）
キー: 英数字、矢印 (`left`/`right`/`up`/`down`)、`return`/`enter`/`tab`/`space`/`esc`/`delete`、`f1`〜`f12`、記号は `minus`/`equal`/`comma`/`period`/`slash`/`backslash`/`semicolon`/`quote`/`leftbracket`/`rightbracket`

## アーキテクチャ

```
┌──────────────────────────────────────────────┐
│  App (LSUIElement, MenuBarExtra)             │
├──────────────────────────────────────────────┤
│  HotkeyManager   │  ConfigManager            │
│  (KeyboardShortcuts) │ (TOMLKit + FS watcher) │
├──────────────────────────────────────────────┤
│  ActionDispatcher (Command pattern)          │
├──────────────────────────────────────────────┤
│  WindowController │ AppLauncher │ PreviewUI  │
│  (AX API wrapper) │ (NSWorkspace)│ (SwiftUI) │
├──────────────────────────────────────────────┤
│  AccessibilityClient (low-level AX wrapper)  │
└──────────────────────────────────────────────┘
```

## 実装進捗

| Phase | 内容 | 状態 |
|---|---|---|
| 0 | プロジェクトセットアップ | 完了 |
| 1 | コア・ウィンドウ操作 | 完了 |
| 2 | 設定ファイル + ホットリロード | 完了 |
| 3 | アプリ起動ショートカット | 完了 |
| 4 | アニメーション（プレビュー） | 完了 |
| 5 | 仕上げ（MenuBar / 設定 / Onboarding） | 完了 |

詳細は [`implementation-plan.md`](./implementation-plan.md) を参照。

## ライセンス

[MIT License](./LICENSE)
