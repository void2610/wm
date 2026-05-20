# wm

macOS 向けキーボード中心のウィンドウマネージャー。
AeroSpace ライクな機能セット + Loop ライクなアニメーション品質を目指した個人開発プロジェクト。

## 主な機能

- **ウィンドウスナップ**: 半分（左/右/上/下）、最大化、中央寄せ、フルスクリーン切替。同じ方向を連打すると巡回する（左連打: 左半分 → 左上 1/4 → 左下 1/4 → 左半分... / 上連打: 上半分 → 全画面）
- **アプリ起動ホットキー**: bundle id 指定。既に起動済みなら activate
- **TOML 設定**: `~/.config/wm/config.toml` に集約。`XDG_CONFIG_HOME` 尊重・dotfiles 対応
- **設定 GUI**: menu bar → 設定… から `animation_enabled` / `animation_duration` / `padding` を編集可（即時 TOML に書き戻し）
- **ホットリロード**: ファイル変更を検知して自動再読み込み（デバウンス付き）
- **プレビュー UI**: スナップ先を半透明ウィンドウで予告（panel.alphaValue + SwiftUI のスライド、easeOut）
- **`AXEnhancedUserInterface`**: 操作中だけ強制 OFF にして AX setSize / setPosition の取りこぼしを回避

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
xcodebuild -project wm.xcodeproj -scheme wm -configuration Debug build
```

### CI 成果物のダウンロード

main へ push するたびに [GitHub Actions](https://github.com/void2610/wm/actions) で Release ビルドが走り、`.app` を zip にして artifact としてアップロードします。

1. Actions タブから直近の成功 run を開く
2. 下部 *Artifacts* セクションの `wm-<short-sha>` をダウンロード
3. zip を展開 → `wm.app` を `/Applications` などに配置

Ad-hoc 署名された .app ですが Developer ID 署名ではないため、初回起動時に Gatekeeper の警告が出ます。Finder で `wm.app` を右クリック → 開く → 警告ダイアログから「開く」で起動できます。

起動するとアクセシビリティ権限の案内ウィンドウが出るので、システム設定 > プライバシーとセキュリティ > アクセシビリティ で wm を ON にしてください。1〜2 秒で自動的にメニューバーアプリに切り替わります。

## 設定例

`~/.config/wm/config.toml`:

```toml
[general]
animation_enabled = true
animation_duration = 0.25
padding = 8
enhanced_ui_excluded = ["com.apple.dt.Xcode"]

[hotkeys]
snap_left   = "cmd+ctrl+left"
snap_right  = "cmd+ctrl+right"
snap_top    = "cmd+ctrl+up"
snap_bottom = "cmd+ctrl+down"
maximize    = "cmd+ctrl+return"
center      = "cmd+ctrl+c"

[[launch]]
key = "cmd+shift+1"
bundle_id = "com.apple.Safari"

[[launch]]
key = "cmd+shift+2"
bundle_id = "com.googlecode.iterm2"
```

利用可能な hotkey 名:
- `snap_left` / `snap_right` / `snap_top` / `snap_bottom`（同じ方向の連打で巡回する）
- `maximize` / `center` / `toggle_fullscreen`

モディファイア表記: `cmd` / `opt` / `ctrl` / `shift`（区切りは `+` または `-`）
キー: 英数字、矢印 (`left`/`right`/`up`/`down`)、`return`/`enter`/`tab`/`space`/`esc`/`delete`、`f1`〜`f12`、記号は `minus`/`equal`/`comma`/`period`/`slash`/`backslash`/`semicolon`/`quote`/`leftbracket`/`rightbracket`

## アーキテクチャ

```
┌──────────────────────────────────────────────┐
│  App (LSUIElement, NSStatusItem)             │
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
